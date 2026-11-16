import AppKit

// Emits mouse events through an injectable sink so click/drag lifecycles can be
// tested without moving the user's cursor.
final class SystemPointer {
    var displayBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
    var position = CGPoint(x: 0.5, y: 0.5)
    var hasPosition = false
    var down = false
    var dragging = false
    var pinchOrigin: CGPoint?
    var frozenPosition: CGPoint?
    var pressedAt = 0.0
    let emit: (CGEventType, CGPoint) -> Void

    init(emit: @escaping (CGEventType, CGPoint) -> Void = SystemPointer.post) {
        self.emit = emit
    }

    static func post(_ type: CGEventType, _ position: CGPoint) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type,
                            mouseCursorPosition: position, mouseButton: .left)
        event?.flags = []
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        event?.post(tap: .cghidEventTap)
    }

    func desktopPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: displayBounds.minX + min(1, max(0, point.x)) * max(0, displayBounds.width - 1),
                y: displayBounds.minY + min(1, max(0, point.y)) * max(0, displayBounds.height - 1))
    }

    func release() {
        if down { emit(.leftMouseUp, desktopPoint(position)) }
        down = false
        dragging = false
        pinchOrigin = nil
        frozenPosition = nil
        hasPosition = false
    }

    func update(point: CGPoint, pinched: Bool, event: String?, now: Double, elapsed: Double) {
        if !hasPosition { position = point; hasPosition = true }
        if pinched && pinchOrigin == nil {
            pinchOrigin = point
            frozenPosition = position
        }
        var destination = point
        if let origin = pinchOrigin, let frozen = frozenPosition {
            if down && pinched && now - pressedAt >= 0.3 {
                dragging = true
            }
            destination = dragging ? CGPoint(x: frozen.x + point.x - origin.x, y: frozen.y + point.y - origin.y) : frozen
        }
        // Keep the last drag position stable while release is being debounced.
        if down && !pinched { destination = position }
        // Input has already passed through the adaptive motion filter.
        position.x = min(1, max(0, destination.x))
        position.y = min(1, max(0, destination.y))
        emit(down ? .leftMouseDragged : .mouseMoved, desktopPoint(position))
        if event == "press" {
            emit(.leftMouseDown, desktopPoint(position))
            down = true
            pressedAt = now
        }
        if event == "click" {
            if down { emit(.leftMouseUp, desktopPoint(position)) }
            down = false
            dragging = false
            pinchOrigin = nil
            frozenPosition = nil
        } else if !pinched && !down {
            pinchOrigin = nil
            frozenPosition = nil
        }
    }
}

func testSystemPointer() {
    var events: [(CGEventType, CGPoint)] = []
    let pointer = SystemPointer { events.append(($0, $1)) }
    pointer.displayBounds = CGRect(x: -1000, y: 100, width: 1000, height: 800)
    let center = CGPoint(x: 0.5, y: 0.5)
    pointer.update(point: center, pinched: false, event: nil, now: 1, elapsed: 0.1)
    pointer.update(point: center, pinched: true, event: "press", now: 1.1, elapsed: 0.1)
    pointer.update(point: center, pinched: false, event: "click", now: 1.2, elapsed: 0.1)
    assert(events.filter { $0.0 == .leftMouseDown }.count == 1)
    assert(events.filter { $0.0 == .leftMouseUp }.count == 1)
    assert(events.first!.1 == CGPoint(x: -500.5, y: 499.5))
    pointer.update(point: center, pinched: true, event: "press", now: 2, elapsed: 0.1)
    pointer.update(point: CGPoint(x: 0.8, y: 0.4), pinched: true, event: nil, now: 2.4, elapsed: 0.1)
    assert(pointer.dragging && pointer.position.x > 0.5)
    let held = pointer.position
    pointer.update(point: CGPoint(x: 0.9, y: 0.4), pinched: false, event: nil, now: 2.5, elapsed: 0.1)
    assert(pointer.position == held)
    pointer.release()
    assert(!pointer.down && !pointer.hasPosition)
    assert(events.last!.0 == .leftMouseUp)
    let count = events.count
    pointer.release()
    assert(events.count == count)
    print("PASS system click, drag, release stability, cancellation, display coordinates")
}
