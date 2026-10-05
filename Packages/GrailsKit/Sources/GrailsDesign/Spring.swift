import Foundation

/// A critically damped spring: it reaches its target as fast as it can without ever overshooting it (given a velocity toward it).
/// Closed form, so a long frame can't make it unstable.
public struct CriticalSpring: Sendable {
    public var value: Double
    public var velocity: Double
    public var target: Double
    public let omega: Double
    /// How close counts as arrived (points for a drag, a tiny number for a zoom factor).
    public let tolerance: Double

    /// `response`: roughly the time it takes to settle, in seconds.
    public init(value: Double = 0, velocity: Double = 0, target: Double = 0, response: Double = Motion.flight * 1.2, tolerance: Double = 0.2) {
        self.value = value; self.velocity = velocity; self.target = target; self.tolerance = tolerance
        omega = 2 * Double.pi / max(response, 0.05)
    }

    public var isSettled: Bool { abs(value - target) < tolerance && abs(velocity) < tolerance * 10 }

    public mutating func step(_ dt: Double) {
        let x0 = value - target
        let k = velocity + omega * x0
        let decay = exp(-omega * dt)
        value = target + (x0 + k * dt) * decay
        velocity = (velocity - k * omega * dt) * decay
        if isSettled { value = target; velocity = 0 }
    }
}
