import Foundation

// Speed-adaptive first-order filtering following Casiez, Roussel, Vogel (CHI 2012).
struct OneEuroPoint {
    var previous: CGPoint?
    var filtered = CGPoint.zero
    var velocity = CGPoint.zero

    mutating func update(_ point: CGPoint, elapsed: Double) -> CGPoint {
        guard let previous else {
            self.previous = point
            filtered = point
            return point
        }
        let dt = min(0.2, max(0.001, elapsed))
        let derivativeAlpha = alpha(cutoff: 1, elapsed: dt)
        velocity.x += derivativeAlpha * ((point.x - previous.x) / dt - velocity.x)
        velocity.y += derivativeAlpha * ((point.y - previous.y) / dt - velocity.y)
        let cutoff = 0.8 + 6 * hypot(velocity.x, velocity.y)
        let positionAlpha = alpha(cutoff: cutoff, elapsed: dt)
        filtered.x += positionAlpha * (point.x - filtered.x)
        filtered.y += positionAlpha * (point.y - filtered.y)
        self.previous = point
        return filtered
    }

    private func alpha(cutoff: Double, elapsed: Double) -> Double {
        let rate = 2 * Double.pi * cutoff * elapsed
        return rate / (1 + rate)
    }
}

struct PointerMotion {
    var relative = true
    var sensitivity = 1.3
    var position = CGPoint(x: 0.5, y: 0.5)
    var filter = OneEuroPoint()
    var anchor: CGPoint?
    // Camera-image units. Slow movements within this radius leave the cursor still.
    let deadZone = 0.006

    mutating func reset(at position: CGPoint) {
        self.position = position
        filter = OneEuroPoint()
        anchor = nil
    }

    mutating func update(_ hand: CGPoint, elapsed: Double) -> CGPoint {
        let sample = filter.update(hand, elapsed: elapsed)
        if !relative {
            let range = 0.6 / sensitivity
            position = CGPoint(x: clamp(0.5 + (sample.x - 0.5) / range),
                               y: clamp(0.5 + (sample.y - 0.5) / range))
            return position
        }
        guard let anchor else { self.anchor = sample; return position }
        let dx = sample.x - anchor.x
        let dy = sample.y - anchor.y
        let distance = hypot(dx, dy)
        guard distance > deadZone else { return position }
        // Soft dead zone preserves accumulated intentional movement without a jump.
        let fraction = (distance - deadZone) / distance
        let moveX = dx * fraction
        let moveY = dy * fraction
        self.anchor = CGPoint(x: anchor.x + moveX, y: anchor.y + moveY)
        let speed = hypot(moveX, moveY) / max(0.001, elapsed)
        let gain = movementGain(speed: speed)
        position.x = clamp(position.x + moveX * gain)
        position.y = clamp(position.y + moveY * gain)
        return position
    }

    func movementGain(speed: Double) -> Double {
        // Reduce gain only for fine adjustments; ordinary movement reaches a
        // fixed ceiling, so a fast sweep cannot trigger a speed boost.
        let blend = min(1, max(0, (speed - 0.012) / 0.048))
        let transition = blend * blend * (3 - 2 * blend)
        return sensitivity * (0.3 + 0.7 * transition)
    }

    private func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

func testPointerMotion() {
    var motion = PointerMotion()
    let center = CGPoint(x: 0.5, y: 0.5)
    motion.reset(at: center)
    _ = motion.update(center, elapsed: 1 / 15)
    for index in 0..<150 {
        let noise = 0.004 * sin(Double(index) * 0.3)
        _ = motion.update(CGPoint(x: 0.5 + noise, y: 0.5), elapsed: 1 / 15)
    }
    assert(motion.position == center, "Small stationary motion should remain inside the dead zone")
    func displacement(steps: Int) -> Double {
        var motion = PointerMotion()
        _ = motion.update(center, elapsed: 1 / 15)
        for index in 1...steps {
            _ = motion.update(CGPoint(x: 0.5 + 0.12 * Double(index) / Double(steps), y: 0.5), elapsed: 1 / 15)
        }
        return motion.position.x - 0.5
    }
    let slow = displacement(steps: 60)
    let fast = displacement(steps: 6)
    assert(slow > 0 && slow < fast, "Fine adjustments should use less gain than ordinary movement")
    assert(fast <= 0.12 * motion.sensitivity, "Fast movement must stay within the normal-speed ceiling")
    assert(abs(motion.movementGain(speed: 0.001) - 0.3 * motion.sensitivity) < 0.000001)
    assert(motion.movementGain(speed: 0.08) == motion.movementGain(speed: 0.8), "Ordinary and fast motion must have identical gain")
    motion.reset(at: CGPoint(x: 0.8, y: 0.2))
    assert(motion.update(CGPoint(x: 0.1, y: 0.9), elapsed: 0.1) == CGPoint(x: 0.8, y: 0.2), "Reacquisition must not warp the pointer")
    var direct = PointerMotion()
    direct.relative = false
    let mapped = direct.update(CGPoint(x: 0.7, y: 0.3), elapsed: 0.1)
    assert(mapped.x > 0.9 && mapped.y < 0.1)
    print(String(format: "PASS stationary jitter, precision slowdown (slow %.3f / fast %.3f), speed ceiling, reacquisition, direct mapping", slow, fast))
}
