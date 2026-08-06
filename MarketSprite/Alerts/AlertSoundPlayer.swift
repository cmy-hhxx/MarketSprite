import AppKit

@MainActor
final class AlertSoundPlayer {
    private var currentSound: NSSound?

    func play(_ direction: AlertDirection, isEnabled: Bool) {
        guard isEnabled else { return }

        let resourceName = direction == .rising ? "bull-moo" : "bear-growl"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "wav") else {
            NSSound.beep()
            return
        }

        currentSound?.stop()
        currentSound = NSSound(contentsOf: url, byReference: true)
        currentSound?.volume = 0.82
        currentSound?.play()
    }

    func stop() {
        currentSound?.stop()
        currentSound = nil
    }
}
