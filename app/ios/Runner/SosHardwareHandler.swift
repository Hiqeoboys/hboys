import AVFoundation
import Flutter
import UIKit

/// Native iOS handler for `id.nama.nama_app/sos_hardware` matching Android parity.
final class SosHardwareHandler {
  static let channelName = "id.nama.nama_app/sos_hardware"

  private let torchQueue = DispatchQueue(label: "id.nama.nama_app.sos_hardware.torch")
  private let stateLock = NSLock()
  private var pendingTorchWorkItem: DispatchWorkItem?
  private var terminateObserver: NSObjectProtocol?

  private var savedCategory: AVAudioSession.Category?
  private var savedMode: AVAudioSession.Mode?
  private var savedCategoryOptions: AVAudioSession.CategoryOptions?

  init(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "setTorch":
        let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
        self.setTorch(enabled: enabled) { ok in
          result(ok)
        }
      case "setMaxVolume":
        result(self.configureEmergencyAudioSession())
      case "restoreVolume":
        self.restoreAudioSession()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    terminateObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.shutdown()
    }
  }

  deinit {
    if let observer = terminateObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    shutdown()
  }

  func setTorch(enabled: Bool, completion: @escaping (Bool) -> Void) {
    var workItem: DispatchWorkItem!
    workItem = DispatchWorkItem { [weak self] in
      guard let self, !workItem.isCancelled else {
        DispatchQueue.main.async { completion(false) }
        return
      }
      let ok = self.applyTorchSynchronously(enabled: enabled)
      DispatchQueue.main.async { completion(ok) }
    }

    stateLock.lock()
    if !enabled {
      pendingTorchWorkItem?.cancel()
    }
    pendingTorchWorkItem = workItem
    stateLock.unlock()

    torchQueue.async(execute: workItem)
  }

  func configureEmergencyAudioSession() -> Bool {
    let session = AVAudioSession.sharedInstance()
    stateLock.lock()
    if savedCategory == nil {
      savedCategory = session.category
      savedMode = session.mode
      savedCategoryOptions = session.categoryOptions
    }
    stateLock.unlock()

    do {
      // .playback ensures the SOS siren plays audibly even when the hardware Silent switch is active.
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setActive(true)
      return true
    } catch {
      #if targetEnvironment(simulator)
      return true
      #else
      return false
      #endif
    }
  }

  func restoreAudioSession() {
    stateLock.lock()
    guard let category = savedCategory,
          let mode = savedMode,
          let options = savedCategoryOptions else {
      stateLock.unlock()
      return
    }
    savedCategory = nil
    savedMode = nil
    savedCategoryOptions = nil
    stateLock.unlock()

    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(category, mode: mode, options: options)
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
  }

  func shutdown() {
    stateLock.lock()
    pendingTorchWorkItem?.cancel()
    pendingTorchWorkItem = nil
    stateLock.unlock()

    torchQueue.sync {
      if let device = AVCaptureDevice.default(for: .video),
         device.hasTorch,
         device.torchMode != .off {
        _ = self.applyTorchSynchronously(enabled: false)
      }
    }
    restoreAudioSession()
  }

  private func applyTorchSynchronously(enabled: Bool) -> Bool {
    guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
      // Graceful fallback for iOS Simulator or hardware without a rear torch.
      return true
    }
    guard device.isTorchAvailable else {
      return false
    }
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      if enabled {
        try device.setTorchModeOn(level: min(1.0, AVCaptureDevice.maxAvailableTorchLevel))
      } else {
        device.torchMode = .off
      }
      return true
    } catch {
      return false
    }
  }
}
