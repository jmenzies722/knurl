import CoreAudio
import Foundation

@MainActor
final class OutputWatch {
    static let shared = OutputWatch()

    private var running = false

    private init() {}

    func start(_ onChange: @escaping @MainActor () -> Void) {
        guard !running else { return }
        running = true
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
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
