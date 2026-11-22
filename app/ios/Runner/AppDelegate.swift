import Contacts
import ContactsUI
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CNContactPickerDelegate {
  private var pendingContactResult: FlutterResult?
  private var sosHardwareHandler: SosHardwareHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HiqeoContactsChannel") {
      let channel = FlutterMethodChannel(
        name: "id.nama.nama_app/contacts",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "pickContact" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.presentContactPicker(result: result)
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HiqeoSosHardwareChannel") {
      sosHardwareHandler = SosHardwareHandler(messenger: registrar.messenger())
    }
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    sosHardwareHandler?.shutdown()
    super.applicationWillTerminate(application)
  }

  private func presentContactPicker(result: @escaping FlutterResult) {
    guard pendingContactResult == nil else {
      result(nil)
      return
    }
    guard let presenter = topViewController() else {
      result(nil)
      return
    }
    pendingContactResult = result
    let picker = CNContactPickerViewController()
    picker.delegate = self
    picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
    presenter.present(picker, animated: true)
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let root = scenes.first(where: { $0.activationState == .foregroundActive })?.windows
      .first(where: { $0.isKeyWindow })?.rootViewController
    var current = root
    while let presented = current?.presentedViewController {
      current = presented
    }
    return current
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
    let callback = pendingContactResult
    pendingContactResult = nil
    let fullName = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
    let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
    callback?(["name": fullName, "phone": phone])
  }

  func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
    let callback = pendingContactResult
    pendingContactResult = nil
    callback?(nil)
  }
}
