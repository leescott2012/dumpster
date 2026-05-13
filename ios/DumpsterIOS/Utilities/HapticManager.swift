import CoreHaptics
import UIKit

final class HapticManager {

    static let shared = HapticManager()

    private var engine: CHHapticEngine?
    private var engineReady = false

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            engine?.stoppedHandler = { [weak self] _ in self?.engineReady = false }
            engine?.resetHandler = { [weak self] in self?.startEngine() }
            startEngine()
        } catch {
            // Haptics unavailable on this device
        }
    }

    private func startEngine() {
        try? engine?.start()
        engineReady = true
    }

    // MARK: - Public Patterns

    /// Light tick — drag hover, selection toggle, filter tap
    func playTick() {
        play([
            event(.hapticTransient, intensity: 0.45, sharpness: 0.9, at: 0),
        ])
    }

    /// Double tap — photo added to dump, title approved
    func playAdded() {
        play([
            event(.hapticTransient, intensity: 0.5,  sharpness: 0.7, at: 0),
            event(.hapticTransient, intensity: 0.75, sharpness: 0.8, at: 0.09),
        ])
    }

    /// Triple ascending — captions generated, batch import complete, peak zone reached
    func playSuccess() {
        play([
            event(.hapticTransient, intensity: 0.4, sharpness: 0.5, at: 0),
            event(.hapticTransient, intensity: 0.65, sharpness: 0.65, at: 0.1),
            event(.hapticTransient, intensity: 0.9, sharpness: 0.8, at: 0.2),
        ])
    }

    /// Soft thud + short buzz — remove photo from dump
    func playRemove() {
        play([
            event(.hapticTransient,  intensity: 0.7, sharpness: 0.3, at: 0),
            event(.hapticContinuous, intensity: 0.3, sharpness: 0.1, at: 0.04, duration: 0.1),
        ])
    }

    /// Strong impact + sustained rumble — delete dump
    func playDelete() {
        play([
            event(.hapticTransient,  intensity: 1.0, sharpness: 0.2, at: 0),
            event(.hapticContinuous, intensity: 0.6, sharpness: 0.15, at: 0.04, duration: 0.18),
        ])
    }

    /// Bouncing decay — drag-and-drop complete
    func playDrop() {
        let timings: [(Double, Float)] = [(0.0, 1.0), (0.1, 0.65), (0.18, 0.4), (0.24, 0.2)]
        play(timings.map { event(.hapticTransient, intensity: $0.1, sharpness: 0.9, at: $0.0) })
    }

    /// Three soft pulses — warning / vibe mismatch
    func playWarning() {
        play([
            event(.hapticContinuous, intensity: 0.45, sharpness: 0.5, at: 0.0,  duration: 0.12),
            event(.hapticContinuous, intensity: 0.60, sharpness: 0.5, at: 0.2,  duration: 0.12),
            event(.hapticContinuous, intensity: 0.75, sharpness: 0.5, at: 0.4,  duration: 0.12),
        ])
    }

    // MARK: - Private helpers

    private func event(
        _ type: CHHapticEvent.EventType,
        intensity: Float,
        sharpness: Float,
        at time: TimeInterval,
        duration: TimeInterval = 0
    ) -> CHHapticEvent {
        let params = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ]
        if type == .hapticContinuous {
            return CHHapticEvent(eventType: type, parameters: params, relativeTime: time, duration: duration)
        }
        return CHHapticEvent(eventType: type, parameters: params, relativeTime: time)
    }

    private func play(_ events: [CHHapticEvent]) {
        guard engineReady, let engine else {
            // Fallback to UIKit for devices without CoreHaptics
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player  = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Silently degrade
        }
    }
}
