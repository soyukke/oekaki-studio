import CoreGraphics
import Foundation

/// Tells a quick tap of two or three fingers on the trackpad from a
/// scroll, a pinch or fingers left resting, as drawing apps use them:
/// two fingers to take back, three to do again.
public struct FingerTaps {
    public enum Tap: Equatable {
        case two, three
    }

    /// Longer than this, the fingers were pressing, not tapping.
    static let longest: TimeInterval = 0.35
    /// Further than this, in shares of the trackpad's size, they moved.
    static let reach: CGFloat = 0.03

    private var started: TimeInterval?
    private var starts: [AnyHashable: CGPoint] = [:]
    private var most = 0
    private var moved = false

    public init() {}

    /// Takes the fingers now on the trackpad, each with its place as a share
    /// of the trackpad's size, and returns a tap when the last one lifts.
    public mutating func update(touching: [(id: AnyHashable, position: CGPoint)], at time: TimeInterval) -> Tap? {
        if started == nil {
            guard !touching.isEmpty else { return nil }
            started = time
        }
        most = max(most, touching.count)
        for finger in touching {
            if let start = starts[finger.id] {
                if hypot(finger.position.x - start.x, finger.position.y - start.y) > Self.reach { moved = true }
            } else {
                starts[finger.id] = finger.position
            }
        }
        guard touching.isEmpty, let started else { return nil }
        let quick = time - started <= Self.longest && !moved
        let fingers = most
        cancel()
        guard quick else { return nil }
        switch fingers {
        case 2: return .two
        case 3: return .three
        default: return nil
        }
    }

    /// Forgets the fingers, as when the system takes the touches over.
    public mutating func cancel() {
        started = nil
        starts = [:]
        most = 0
        moved = false
    }
}
