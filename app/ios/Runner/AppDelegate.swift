import AVFoundation
import Contacts
import ContactsUI
import Flutter
import Photos
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HiqeoMediaChannel") {
      let mediaChannel = FlutterMethodChannel(
        name: "id.nama.nama_app/media",
        binaryMessenger: registrar.messenger()
      )
      mediaChannel.setMethodCallHandler { [weak self] call, result in
        self?.handleMediaCall(call, result: result)
      }
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

  private func handleMediaCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getAppVersion":
      let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
      let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
      result("\(short)+\(build)")

    case "extractVideoThumbnail":
      guard let args = call.arguments as? [String: Any],
            let source = args["source"] as? String,
            !source.isEmpty else {
        result(nil)
        return
      }
      let maxWidth = (args["maxWidth"] as? NSNumber)?.intValue ?? 960
      DispatchQueue.global(qos: .userInitiated).async {
        let data = Self.extractVideoThumbnailData(source: source, maxWidth: maxWidth)
        DispatchQueue.main.async {
          result(data.map { FlutterStandardTypedData(bytes: $0) })
        }
      }

    case "compressVideo":
      guard let args = call.arguments as? [String: Any],
            let sourcePath = args["sourcePath"] as? String,
            !sourcePath.isEmpty else {
        result(nil)
        return
      }
      let maxHeight = (args["maxHeight"] as? NSNumber)?.intValue ?? 720
      let maxBytes = (args["maxBytes"] as? NSNumber)?.intValue ?? (25 * 1024 * 1024)
      Self.compressVideoOnIos(
        sourcePath: sourcePath,
        maxHeight: maxHeight,
        maxBytes: maxBytes
      ) { outPath in
        DispatchQueue.main.async {
          result(outPath)
        }
      }

    case "saveMedia":
      guard let args = call.arguments as? [String: Any],
            let mimeType = args["mimeType"] as? String else {
        result(nil)
        return
      }
      let filePath = args["filePath"] as? String
      let rawBytes = (args["bytes"] as? FlutterStandardTypedData)?.data
      let fileName = (args["name"] as? String) ?? "Hiqeo_media"
      Self.saveMediaToPhotos(
        name: fileName,
        mimeType: mimeType,
        filePath: filePath,
        bytes: rawBytes
      ) { saved in
        DispatchQueue.main.async {
          result(saved)
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func extractVideoThumbnailData(source: String, maxWidth: Int) -> Data? {
    let url: URL
    if source.hasPrefix("https://") {
      guard let remoteUrl = URL(string: source) else { return nil }
      url = remoteUrl
    } else if source.hasPrefix("http://") {
      return nil
    } else {
      url = URL(fileURLWithPath: source)
    }

    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    if maxWidth > 0 {
      generator.maximumSize = CGSize(width: CGFloat(maxWidth), height: CGFloat(maxWidth))
    }
    guard let cgImage = try? generator.copyCGImage(
      at: CMTime(seconds: 0, preferredTimescale: 600),
      actualTime: nil
    ) else {
      return nil
    }
    return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85)
  }

  private static func compressVideoOnIos(
    sourcePath: String,
    maxHeight: Int,
    maxBytes: Int,
    completion: @escaping (String?) -> Void
  ) {
    let srcUrl = URL(fileURLWithPath: sourcePath)
    let asset = AVURLAsset(url: srcUrl)
    let preset = maxHeight >= 1080
      ? AVAssetExportPreset1920x1080
      : AVAssetExportPreset1280x720

    guard let session = AVAssetExportSession(asset: asset, presetName: preset)
        ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720)
        ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
      completion(nil)
      return
    }

    let outFileName = "hiqeo_vid_\(Int(Date().timeIntervalSince1970 * 1000)).mp4"
    let outUrl = FileManager.default.temporaryDirectory.appendingPathComponent(outFileName)
    try? FileManager.default.removeItem(at: outUrl)

    session.outputURL = outUrl
    session.outputFileType = .mp4
    session.shouldOptimizeForNetworkUse = true
    session.fileLengthLimit = Int64(maxBytes)

    session.exportAsynchronously {
      if session.status == .completed,
         let attrs = try? FileManager.default.attributesOfItem(atPath: outUrl.path),
         let size = attrs[.size] as? NSNumber,
         size.intValue > 0 && size.intValue <= maxBytes {
        completion(outUrl.path)
      } else {
        try? FileManager.default.removeItem(at: outUrl)
        completion(nil)
      }
    }
  }

  private static func saveMediaToPhotos(
    name: String,
    mimeType: String,
    filePath: String?,
    bytes: Data?,
    completion: @escaping (String?) -> Void
  ) {
    let isVideo = mimeType.hasPrefix("video/")
    var tempUrlToClean: URL?
    let sourceUrl: URL
    if let path = filePath, !path.isEmpty {
      sourceUrl = URL(fileURLWithPath: path)
    } else if let data = bytes, !data.isEmpty {
      let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
      do {
        try data.write(to: tmp, options: .atomic)
        tempUrlToClean = tmp
        sourceUrl = tmp
      } catch {
        completion(nil)
        return
      }
    } else {
      completion(nil)
      return
    }

    let performSave = {
      var localId: String?
      PHPhotoLibrary.shared().performChanges({
        let req = isVideo
          ? PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: sourceUrl)
          : PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: sourceUrl)
        localId = req?.placeholderForCreatedAsset?.localIdentifier
      }) { success, _ in
        if let tmp = tempUrlToClean {
          try? FileManager.default.removeItem(at: tmp)
        }
        completion(success ? (localId ?? "saved") : nil)
      }
    }

    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        if status == .authorized || status == .limited {
          performSave()
        } else {
          if let tmp = tempUrlToClean {
            try? FileManager.default.removeItem(at: tmp)
          }
          completion(nil)
        }
      }
    } else {
      PHPhotoLibrary.requestAuthorization { status in
        if status == .authorized {
          performSave()
        } else {
          if let tmp = tempUrlToClean {
            try? FileManager.default.removeItem(at: tmp)
          }
          completion(nil)
        }
      }
    }
  }
}
