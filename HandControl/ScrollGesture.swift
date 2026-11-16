import Foundation

struct ScrollGesture {
    var active = false
    var entering = 0
    var missingSeconds = 0.0
    var anchor: Double?
    var remainder = 0.0
    var filter = OneEuroPoint()

    var engaged: Bool { active || entering > 0 }

    mutating func reset() { self = ScrollGesture() }

    // Consume pose transitions too, preventing them from becoming clicks.
    mutating func update(pose: Bool, y: Double, elapsed: Double) -> (consumed: Bool, delta: Int32) {
        if !pose {
            let consumed = engaged
            missingSeconds += max(0, elapsed)
            entering = 0
            anchor = nil
            filter = OneEuroPoint()
            if missingSeconds >= 0.35 { reset() }
            return (consumed, 0)
        }
        missingSeconds = 0
        entering += 1
        guard active || entering >= 3 else { return (true, 0) }
        active = true
        let filtered = filter.update(CGPoint(x: 0, y: y), elapsed: elapsed).y
        guard let anchor else { self.anchor = filtered; return (true, 0) }
        let difference = filtered - anchor
        guard abs(difference) > 0.003 else { return (true, 0) }
        let movement = difference - (difference > 0 ? 0.003 : -0.003)
        self.anchor = anchor + movement
        let pixels = min(90, max(-90, movement * 2250)) + remainder
        let whole = pixels.rounded(.towardZero)
        remainder = pixels - whole
        return (true, Int32(whole))
    }
}

func testScrollGesture() {
    var scroll = ScrollGesture()
    assert(scroll.update(pose: true, y: 0.5, elapsed: 0.07).delta == 0)
    assert(!scroll.active)
    _ = scroll.update(pose: true, y: 0.5, elapsed: 0.07)
    _ = scroll.update(pose: true, y: 0.5, elapsed: 0.07)
    assert(scroll.active)
    assert(scroll.update(pose: true, y: 0.6, elapsed: 0.07).delta > 0)
    assert(scroll.update(pose: true, y: 0.3, elapsed: 0.07).delta < 0)
    assert(scroll.update(pose: false, y: 0.8, elapsed: 0.07).delta == 0)
    assert(scroll.active)
    // Returning after a short recognition gap reanchors without a wheel jump.
    assert(scroll.update(pose: true, y: 0.9, elapsed: 0.07).delta == 0)
    assert(scroll.active)
    for _ in 0..<5 { assert(scroll.update(pose: false, y: 0.8, elapsed: 0.08).delta == 0) }
    assert(!scroll.engaged)
    assert(!scroll.update(pose: false, y: 0.8, elapsed: 0.07).consumed)
    scroll.reset()
    assert(scroll.anchor == nil && scroll.remainder == 0)
    print("PASS scroll entry, direction, pose-loss freeze, gap recovery, timed exit, reset")
}
