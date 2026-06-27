import UIKit
import UserNotifications
import AVFoundation

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        BackgroundKeepAlive.shared.setup()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundKeepAlive.shared.startIfNeeded()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        BackgroundKeepAlive.shared.stop()
    }

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        SDDownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
}

// MARK: - Background keep-alive

/// Keeps the process alive when backgrounded using AVAudioSession silent audio.
/// This ensures URLSession's download thread keeps running indefinitely.
/// The cooperative thread pool may still be suspended (affecting @MainActor tasks),
/// but the URLSession delegate thread and our CFRunLoop thread are OS-level threads
/// that continue running as long as the process is alive.
final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()
    private init() {}

    private var player: AVAudioPlayer?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var isRunning = false

    func setup() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[KeepAlive] AVAudioSession setup failed: \(error)")
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(audioInterrupted),
            name: AVAudioSession.interruptionNotification, object: nil)
    }

    func startIfNeeded() {
        guard SDDownloadManager.shared.hasActiveDownloads else { return }
        start()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startAudio()
        renewBgTask()
        print("[KeepAlive] started")
    }

    func stop() {
        isRunning = false
        player?.stop()
        player = nil
        endBgTask()
        print("[KeepAlive] stopped")
    }

    private func startAudio() {
        player?.stop()
        player = nil
        do { try AVAudioSession.sharedInstance().setActive(true) } catch {}

        // 30-second silent WAV loop
        let sr = 44100, secs = 30, ds = sr * secs * 2
        var wav = Data(count: 44 + ds)
        wav.withUnsafeMutableBytes { ptr in
            guard let b = ptr.baseAddress else { return }
            let h: [UInt8] = [
                0x52,0x49,0x46,0x46,
                UInt8((ds+36)&0xFF),    UInt8((ds+36)>>8&0xFF),
                UInt8((ds+36)>>16&0xFF),UInt8((ds+36)>>24&0xFF),
                0x57,0x41,0x56,0x45,   0x66,0x6D,0x74,0x20,
                0x10,0x00,0x00,0x00,   0x01,0x00, 0x01,0x00,
                0x44,0xAC,0x00,0x00,   0x88,0x58,0x01,0x00,
                0x02,0x00, 0x10,0x00,  0x64,0x61,0x74,0x61,
                UInt8(ds&0xFF),         UInt8(ds>>8&0xFF),
                UInt8(ds>>16&0xFF),     UInt8(ds>>24&0xFF)
            ]
            h.enumerated().forEach {
                b.storeBytes(of: $0.element, toByteOffset: $0.offset, as: UInt8.self)
            }
        }
        do {
            player = try AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
            player?.numberOfLoops = -1
            player?.volume = 0.01
            player?.play()
        } catch { print("[KeepAlive] audio error: \(error)") }
    }

    private func renewBgTask() {
        endBgTask()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "sddownload") { [weak self] in
            // Expiry — audio should keep us alive, but renew just in case
            self?.endBgTask()
            self?.renewBgTask()
        }
    }

    private func endBgTask() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    @objc private func audioInterrupted(_ n: Notification) {
        guard
            let v = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            AVAudioSession.InterruptionType(rawValue: v) == .ended,
            isRunning
        else { return }
        startAudio()
    }
}
