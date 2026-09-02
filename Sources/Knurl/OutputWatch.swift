import AVFoundation
import CoreAudio
import Foundation
import Observation

@MainActor
@Observable
final class OutputWatch {
    static let shared = OutputWatch()

    private(set) var airPlayNearby = false
    private var running = false
    private let detector = AVRouteDetector()
    private var detectorObserver: NSObjectProtocol?

    private init() {}

    func start(_ onChange: @escaping @MainActor () -> Void) {
        guard !running else { return }
        running = true
        listen(kAudioHardwarePropertyDefaultOutputDevice, onChange)
        listen(kAudioHardwarePropertyDefaultSystemOutputDevice, onChange)
        listen(kAudioHardwarePropertyDevices, onChange)
        detector.isRouteDetectionEnabled = true
        airPlayNearby = detector.multipleRoutesDetected
        detectorObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.AVRouteDetectorMultipleRoutesDetectedDidChange,
            object: detector,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.airPlayNearby = self?.detector.multipleRoutesDetected ?? false
                onChange()
            }
        }
    }

    private func listen(_ selector: AudioObjectPropertySelector, _ onChange: @escaping @MainActor () -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { _, _ in
            Task { @MainActor in
                onChange()
            }
        }
    }
}
