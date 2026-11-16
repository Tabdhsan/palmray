import Foundation

struct HandPacket: Codable {
    var version = 1
    var sequence: Int
    var valid: Bool
    var x: Double
    var y: Double
    var pinched: Bool
    var analysisMS: Double
    var pinchValid: Bool? = nil
    var scrollPose: Bool? = nil

    var canPinch: Bool { valid && (pinchValid ?? valid) }
}

// A fresh open hand is required after any loss of tracking or connection.
struct PinchGate {
    var armed = false
    var pressed = false
    var openCount = 0
    var closedCount = 0

    mutating func reset() { self = PinchGate() }

    mutating func update(valid: Bool, pinched: Bool) -> String? {
        guard valid else { reset(); return "cancel" }
        if pinched {
            openCount = 0
            closedCount += 1
            if armed && !pressed && closedCount >= 2 {
                pressed = true
                return "press"
            }
        } else {
            closedCount = 0
            openCount += 1
            if openCount >= 2 {
                armed = true
                if pressed {
                    pressed = false
                    return "click"
                }
            }
        }
        return nil
    }
}

// Wrist-to-tip / wrist-to-PIP ratios for index, middle, ring, little.
// Missing joints are unknown, never treated as curled. No particular hidden
// finger is required, but entry needs two visible curled fingers.
func isFistScrollPose(_ ratios: [Double?], sustaining: Bool = false) -> Bool {
    guard ratios.count == 4 else { return false }
    let visible = ratios.compactMap { $0 }
    guard visible.allSatisfy({ $0.isFinite }),
          !visible.contains(where: { $0 > (sustaining ? 1.30 : 1.18) }) else { return false }
    return visible.filter { $0 < (sustaining ? 1.18 : 1.08) }.count >= (sustaining ? 1 : 2)
}

// Distinguish thumb/index pinching from closing the whole hand. Require visible
// extension of another finger; unknown or folded non-index fingers cannot arm it.
func allowsPinch(_ ratios: [Double?]) -> Bool {
    guard ratios.count == 4 else { return false }
    let others = ratios.dropFirst().compactMap { $0 }
    return others.allSatisfy { $0.isFinite && $0 >= 1.08 }
        && others.contains(where: { $0 > 1.25 })
}
