class AccountAppController extends AppController

  handler = (callback)->
    if KD.isLoggedIn()
      KD.singleton('appManager').open 'Account', callback
    else
      KD.singletons.router.handleRoute '/'

  KD.registerAppClass this,
    name                         : "Account"
    routes                       :
      "/:name?/Account"          : -> KD.singletons.router.handleRoute '/Account/Profile'
      "/:name?/Account/:section" : ({params:{section}})-> handler (app)-> app.openSection section
      "/:name?/Account/Referrer" : -> handler (app) -> app.showReferrerModal()
    behavior                     : "hideTabs"
    hiddenHandle                 : yes

  items =
    personal :
      title  : "Personal"
      items  : [
        { slug : 'Profile',   title : "User profile",        listType: "username" }
        { slug : 'Email',     title : "Email notifications", listType: "emailNotifications" }
        { slug : 'Externals', title : "Linked accounts",     listType: "linkedAccounts" }
      ]
    billing :
      title : "Billing"
      items : [
        { slug : "Payment",       title : "Payment methods",     listType: "methods" }
        { slug : "Subscriptions", title : "Your subscriptions",  listType: "subscriptions" }
        { slug : "Billing",       title : "Billing history",     listType: "history" }
      ]
    develop :
      title : "Develop"
      items : [
        { slug : 'SSH',       title : "SSH keys",           listHeader: "Your SSH Keys",          listType: "keys" }
        { slug : 'Keys',      title : "Koding Keys",        listHeader: "Your Koding Keys",       listType: "kodingKeys" }
        { slug : 'Referral',  title : "Referral System",    listHeader: "Your Referral Options",  listType: "referralSystem" }
      ]
    danger  :
      title : "Danger"
      items : [
        { slug: 'Delete', title : "Delete account", listType: "deleteAccount" }
      ]

  constructor:(options={}, data)->

    options.view = new KDView cssClass : "content-page"

    super options, data


  createTab:(itemData)->
    {title, listType} = itemData

    new KDTabPaneView
      view       : new AccountListWrapper
        cssClass : "settings-list-wrapper #{KD.utils.slugify title}"
      , itemData


  openSection:(section)->

    for item in @navController.itemsOrdered when section is item.getData().slug
      @tabView.addPane @createTab item.getData()
      @navController.selectSingleItem item
      break


  loadView:(mainView)->

    # SET UP VIEWS
    @navController = new KDListViewController
      view        : new KDListView
        tagName   : 'aside'
        type      : 'inner-nav'
        itemClass : AccountNavigationItem
      wrapper     : no
      scrollView  : no

    mainView.addSubView navView = @navController.getView()

    mainView.addSubView @tabView = new KDTabView
      hideHandleContainer : yes

    for own sectionKey, section of items
      @navController.instantiateListItems section.items
      navView.addSubView new KDCustomHTMLView tagName : "hr"

    navView.setPartial """
      <a href="/tos.html" target="_blank">Terms of service <span class="icon new-page"></span></a>
      <a href="/privacy.html" target="_blank">Privacy policy <span class="icon new-page"></span></a>
      """

  showReferrerModal:(options={})->
    return  if @referrerModal and not @referrerModal.isDestroyed

    options.top         ?= 50
    options.left        ?= 35
    options.arrowMargin ?= 110

    @referrerModal = new ReferrerModal options

  displayConfirmEmailModal:(name, username, callback=noop)->
    name or= KD.whoami().profile.firstName
    message =
      """
      You need to confirm your email address to continue using Koding and to fully activate your account.<br/><br/>

      When you registered, we sent you a link to confirm your email address. Please use that link.<br/><br/>

      If you had trouble with the email, please click below to resend it.<br/><br/>
      """

    modal = new KDModalView
      title            : "#{name}, please confirm your email address!"
      width            : 600
      overlay          : yes
      cssClass         : "new-kdmodal"
      content          : "<div class='modalformline'>#{Encoder.htmlDecode message}</div>"
      buttons          :
        "Resend Confirmation Email" :
          style        : "modal-clean-red"
          callback     : => @resendHandler modal, username
        Close          :
          style        : "modal-cancel"
          callback     : -> modal.destroy()

    callback modal

  resendHandler : (modal, username)->

    KD.remote.api.JPasswordRecovery.resendVerification username, (err)=>
      modal.buttons["Resend Confirmation Email"].hideLoader()
      return KD.showError err if err
      new KDNotificationView
        title     : "Check your email"
        content   : "We've sent you a confirmation mail."
        duration  : 4500

  redeemReferralPoint:(modal)->
    {vmToResize, sizes} = modal.modal.modalTabs.forms.Redeem.inputs

    data = {
      vmName : vmToResize.getValue(),
      size   : sizes.getValue(),
      type   : "disk"
    }

    KD.remote.api.JReferral.redeem data, (err, refRes)=>
      return KD.showError err if err
      modal.modal.destroy()
      KD.getSingleton("vmController").resizeDisk data.vm, (err, res)=>
        return KD.showError err if err
        KD.getSingleton("vmController").emit "ReferralCountUpdated"
        KD.notify_ """
            #{refRes.addedSize} #{refRes.unit} extra #{refRes.type} is successfully added to your #{refRes.vm} VM.
          """
        @showReferrerModal title: "Want more?"


  showRedeemReferralPointModal:->
    vmController = KD.getSingleton("vmController")
    vmController.fetchVMs yes, (err, vms)=>
      return KD.showError err if err
      return KD.notify_ "You don't have any VMs. Please create one VM" if not vms or vms.length < 1

      KD.remote.api.JReferral.fetchRedeemableReferrals { type: "disk" }, (err, referals)=>
        return KD.showError err if err
        return KD.notify_ "You dont have any referrals" if not referals or referals.length < 1

        @modal = modal = new KDModalViewWithForms
          title                   : "Redeem Your Referral Points"
          cssClass                : "redeem-modal"
          content                 : ""
          overlay                 : yes
          width                   : 500
          height                  : "auto"
          tabs                    :
            forms                 :
              Redeem               :
                callback          : =>
                  @modal.modalTabs.forms.Redeem.buttons.redeemButton.showLoader()
                  @redeemReferralPoint @
                buttons           :
                  redeemButton    :
                    title         : "Redeem"
                    style         : "modal-clean-gray"
                    type          : "submit"
                    loader        :
                      color       : "#444444"
                      diameter    : 12
                    callback      : -> @hideLoader()
                  cancel          :
                    title         : "Cancel"
                    style         : "modal-cancel"
                    callback      : (event)-> modal.destroy()
                fields            :
                  vmToResize    :
                    label         : "Select a WM to resize"
                    cssClass      : "clearfix"
                    itemClass     : KDSelectBox
                    type          : "select"
                    name          : "vmToResize"
                    validate      :
                      rules       :
                        required  : yes
                      messages    :
                        required  : "You must select a VM!"
                    selectOptions : (cb)->
                      options = for vm in vms
                        ( title : vm, value : vm)
                      cb options
                  sizes           :
                    label         : "Select Size"
                    cssClass      : "clearfix"
                    itemClass     : KDSelectBox
                    type          : "select"
                    name          : "size"
                    validate      :
                      rules       :
                        required  : yes
                      messages    :
                        required  : "You must select a size!"
                    selectOptions : (cb)=>
                      options = []
                      previousTotal = 0
                      referals.forEach (referal, i)->
                        previousTotal += referal.amount
                        options.push ( title : "#{previousTotal} #{referal.unit}" , value : previousTotal)
                      cb options


  showRegistrationNeededModal:->
    return if @modal

    handler = (modal, route)->
      modal.destroy()
      KD.utils.wait 5000, KD.getSingleton("router").handleRoute route

    message = "Please login to proceed to the next step"
    @modal = new KDBlockingModalView
      title           : "Koding Registration"
      content         : "<div class='modalformline'>#{message}</div>"
      height          : "auto"
      overlay         : yes
      buttons         :
        "Login"       :
          style       : "modal-clean-gray"
          callback    : => handler @modal, "/Login"
        "Register"    :
          style       : "modal-clean-gray"
          callback    : => handler @modal, "/Register"


    @modal.on "KDObjectWillBeDestroyed", => @modal = null