import AppKit
import Network
import Carbon
import ApplicationServices

final class TestView: NSView {
    let scrollPractice = NSScrollView()
    let practiceText = NSTextView()
    var showingPractice = false
    var scrollActive = false
    var relativeMode = true
    var systemMode = false
    var sensitivity = 1.5
    var pointer = CGPoint(x: 0.5, y: 0.5)
    var tracking = false
    var pressed = false
    var hits = Array(repeating: 0, count: 6)
    var clicks = 0
    var misses = 0
    var packets = 0
    var rate = 0.0
    var analysisMS = 0.0
    var connectionText = "Waiting for iPhone · tap Start RGB → Mac"
    var eventText = "Open your hand to begin"
    override var isFlipped: Bool { true }

    func targetRect(_ index: Int) -> NSRect {
        let width = (bounds.width - 120) / 3
        let height = (bounds.height - 310) / 2
        return NSRect(x: 40 + CGFloat(index % 3) * (width + 20), y: 200 + CGFloat(index / 3) * (height + 20), width: width, height: height)
    }
    func target(at point: CGPoint) -> Int? {
        (0..<6).first { targetRect($0).contains(screenPoint(point)) }
    }
    func screenPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: 40 + point.x * (bounds.width - 80), y: 200 + point.y * (bounds.height - 270))
    }
    func text(_ text: String, at point: CGPoint, size: CGFloat, color: NSColor = .white) {
        (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
        bounds.fill()
        text("Hand control", at: CGPoint(x: 40, y: 25), size: 28)
        text(connectionText, at: CGPoint(x: 40, y: 65), size: 15, color: .systemTeal)
        text(systemMode ? "System cursor active · pinch to click · hold and move to drag · ⌃⌥⌘P pauses" : "Move your open hand to aim. Pinch, then release to click. Press R to reset counts.", at: CGPoint(x: 40, y: 98), size: 14, color: .lightGray)
        text("Pointer sensitivity", at: CGPoint(x: 40, y: 123), size: 13, color: .lightGray)
        text(String(format: "%.1f× · %@", sensitivity, relativeMode ? "normal speed · extra slow for precision" : "direct camera-to-screen mapping"), at: CGPoint(x: 380, y: 123), size: 13, color: .lightGray)
        if showingPractice {
            text(eventText, at: CGPoint(x: 40, y: bounds.height - 45), size: 15, color: scrollActive ? .systemOrange : .white)
            return
        }
        let hovered = tracking ? target(at: pointer) : nil
        for index in 0..<6 {
            let rect = targetRect(index)
            let selected = hovered == index
            (selected ? (pressed ? NSColor.systemOrange : NSColor.systemTeal) : NSColor(calibratedWhite: 0.16, alpha: 1)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20).fill()
            text(["Upper left", "Upper middle", "Upper right", "Lower left", "Lower middle", "Lower right"][index], at: CGPoint(x: rect.minX + 18, y: rect.minY + 20), size: 18)
            text("\(hits[index]) clicks", at: CGPoint(x: rect.minX + 18, y: rect.minY + 56), size: 24)
        }
        if tracking {
            let p = screenPoint(pointer)
            NSColor.white.setStroke()
            let circle = NSBezierPath(ovalIn: NSRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24))
            circle.lineWidth = 3
            circle.stroke()
        }
        text("\(eventText) · \(clicks) clicks · \(misses) outside targets", at: CGPoint(x: 40, y: bounds.height - 53), size: 15)
        text(String(format: "%.1f updates/s · phone processing %.0f ms · %d packets", rate, analysisMS, packets), at: CGPoint(x: 40, y: bounds.height - 29), size: 12, color: .lightGray)
    }
    func configureScrollPractice() {
        scrollPractice.hasVerticalScroller = true
        scrollPractice.autohidesScrollers = true
        scrollPractice.drawsBackground = true
        scrollPractice.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
        practiceText.isEditable = false
        practiceText.isSelectable = true
        practiceText.font = .systemFont(ofSize: 22)
        practiceText.textColor = .white
        practiceText.backgroundColor = scrollPractice.backgroundColor
        practiceText.textContainerInset = NSSize(width: 24, height: 24)
        practiceText.textContainer?.widthTracksTextView = true
        practiceText.string = """
        Scroll practice

        Point at this document, then make a relaxed fist. Keep the whole hand in the camera view.

        Hold the pose briefly until the status says Scrolling. Move your hand upward to move the page upward. Move downward to bring earlier content back into view.

        Returning to an open hand ends scrolling and resumes pointing. The cursor stays in place while you scroll.

        Small adjustments

        Use comfortable, small movements. Resting your forearm can help keep the hand inside the camera view. Scroll movement is capped per update.

        Repositioning

        Lowering your hand out of view stops the gesture. Bring it back near the center and form the fist again to continue from there.

        Clicking and dragging

        Use an open hand to aim, then pinch and release to click. Hold a pinch and move to drag. For scrolling, close the whole hand into a fist. For clicking, pinch thumb and index while keeping the other fingers open.

        Everyday use

        In system cursor mode, place the pointer over a page or scrollable panel first. Hold the fist and move your hand vertically. The same gesture can scroll documents, browser pages, and app sidebars.

        Stopping control

        Control–Option–Command–P pauses system cursor control. You can also use the pause button or Stop on the phone.

        End of practice document

        Move your hand downward in the scrolling pose to return to the top.
        """
        scrollPractice.documentView = practiceText
        scrollPractice.isHidden = true
        addSubview(scrollPractice)
    }

    override func layout() {
        super.layout()
        scrollPractice.frame = NSRect(x: 40, y: 200, width: bounds.width - 80, height: bounds.height - 270)
        let width = scrollPractice.contentSize.width
        practiceText.frame.size.width = width
        if let container = practiceText.textContainer, let layout = practiceText.layoutManager {
            container.containerSize = NSSize(width: max(0, width - 48), height: .greatestFiniteMagnitude)
            layout.ensureLayout(for: container)
            practiceText.frame.size.height = max(scrollPractice.contentSize.height, layout.usedRect(for: container).height + 48)
        }
    }

    func scrollDocument(by delta: Int32) {
        let clip = scrollPractice.contentView
        let maximum = max(0, practiceText.bounds.height - clip.bounds.height)
        clip.scroll(to: CGPoint(x: 0, y: min(maximum, max(0, clip.bounds.origin.y - CGFloat(delta)))))
        scrollPractice.reflectScrolledClipView(clip)
    }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers?.lowercased() == "r" {
            hits = Array(repeating: 0, count: 6); clicks = 0; misses = 0
            needsDisplay = true
        }
    }
}

final class Receiver: NSObject, NSApplicationDelegate {
    let canvas = TestView()
    let systemPointer = SystemPointer()
    var pointerMotion = PointerMotion()
    var scrollGesture = ScrollGesture()
    let systemButton = NSButton(title: "Enable system cursor", target: nil, action: nil)
    var statusItem: NSStatusItem?
    var hotKey: EventHotKeyRef?
    var hotKeyHandler: EventHandlerRef?
    var globalPauseAvailable = false
    var workspaceObservers: [NSObjectProtocol] = []
    var window: NSWindow!
    var listener: NWListener?
    var connection: NWConnection?
    var buffer = Data()
    var gate = PinchGate()
    var lastSequence = -1
    var lastPacket = 0.0
    var rateStart = 0.0
    var rateCount = 0
    var timer: Timer?
    var frozen: CGPoint?
    let logURL = URL(fileURLWithPath: "/private/tmp/rayneo-hand-receiver.log")

    func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(line.utf8))
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appMenu = NSMenuItem(); menu.addItem(appMenu)
        appMenu.submenu = NSMenu()
        appMenu.submenu?.addItem(withTitle: "Quit Hand Control", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Hand Control"
        window.minSize = NSSize(width: 900, height: 600)
        window.contentView = canvas
        UserDefaults.standard.register(defaults: ["pointerSensitivity": 1.5])
        canvas.sensitivity = min(3, max(1, UserDefaults.standard.double(forKey: "pointerSensitivity")))
        let sensitivitySlider = NSSlider(value: canvas.sensitivity, minValue: 1, maxValue: 3, target: self, action: #selector(changeSensitivity(_:)))
        sensitivitySlider.frame = NSRect(x: 180, y: 118, width: 180, height: 24)
        sensitivitySlider.isContinuous = true
        sensitivitySlider.setAccessibilityLabel("Pointer sensitivity")
        canvas.addSubview(sensitivitySlider)
        systemButton.target = self
        systemButton.action = #selector(toggleSystemCursor)
        systemButton.frame = NSRect(x: 40, y: 155, width: 190, height: 30)
        systemButton.bezelStyle = .rounded
        canvas.addSubview(systemButton)
        let accessButton = NSButton(title: "Accessibility settings", target: self, action: #selector(openAccessibility))
        accessButton.frame = NSRect(x: 245, y: 155, width: 185, height: 30)
        accessButton.bezelStyle = .rounded
        canvas.addSubview(accessButton)
        let motionMode = NSPopUpButton(frame: NSRect(x: 450, y: 155, width: 230, height: 30), pullsDown: false)
        motionMode.addItems(withTitles: ["Relative · mouse-style", "Direct · position-based"])
        UserDefaults.standard.register(defaults: ["relativePointer": true])
        canvas.relativeMode = UserDefaults.standard.bool(forKey: "relativePointer")
        motionMode.selectItem(at: canvas.relativeMode ? 0 : 1)
        motionMode.target = self
        motionMode.action = #selector(changeMotionMode(_:))
        motionMode.setAccessibilityLabel("Pointer movement mode")
        canvas.addSubview(motionMode)
        canvas.configureScrollPractice()
        let practiceButton = NSButton(title: "Scroll practice", target: self, action: #selector(toggleScrollPractice(_:)))
        practiceButton.frame = NSRect(x: 695, y: 155, width: 160, height: 30)
        practiceButton.bezelStyle = .rounded
        canvas.addSubview(practiceButton)
        configurePauseShortcut()
        configureStatusMenu()
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.pauseSystemCursor() })
        NotificationCenter.default.addObserver(self, selector: #selector(pauseSystemCursor), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        window.center(); window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.service = NWListener.Service(name: "RayNeo Mac Test", type: "_rayneohand._tcp")
            listener.stateUpdateHandler = { [weak self] state in
                self?.log("LISTENER \(state)")
                if case .failed(let error) = state { self?.canvas.connectionText = "Network error: \(error)"; self?.canvas.needsDisplay = true }
                if case .ready = state { self?.log("PORT \(listener.port?.rawValue ?? 0)") }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: .main)
        } catch { canvas.connectionText = "Could not start receiver: \(error)"; log("ERROR \(error)") }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.canvas.systemMode && !AXIsProcessTrusted() {
                self.pauseSystemCursor()
                self.canvas.eventText = "Accessibility permission required"
            }
            if ProcessInfo.processInfo.systemUptime - self.lastPacket > 0.4 && self.canvas.tracking {
                self.cancelTracking("Tracking timed out · open your hand to resume")
            }
        }
    }
    func configurePauseShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<Receiver>.fromOpaque(context).takeUnretainedValue().pauseSystemCursor()
            return noErr
        }, 1, &event, context, &hotKeyHandler)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey | cmdKey),
                                            EventHotKeyID(signature: 0x524E454F, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        globalPauseAvailable = installed == noErr && registered == noErr
        log("PAUSE_SHORTCUT installed=\(installed) registered=\(registered)")
    }

    func configureStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "Hand: Test"
        let menu = NSMenu()
        let pause = NSMenuItem(title: "Pause system cursor (⌃⌥⌘P)", action: #selector(pauseSystemCursor), keyEquivalent: "")
        pause.target = self; menu.addItem(pause)
        let show = NSMenuItem(title: "Show Hand Control", action: #selector(showWindow), keyEquivalent: "")
        show.target = self; menu.addItem(show)
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem?.menu = menu
    }

    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }

    @objc func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func toggleSystemCursor() {
        if canvas.systemMode { pauseSystemCursor(); return }
        guard globalPauseAvailable else {
            canvas.eventText = "Pause shortcut unavailable · close any app using ⌃⌥⌘P and restart"
            canvas.needsDisplay = true
            return
        }
        guard AXIsProcessTrusted() else {
            canvas.eventText = "Enable Hand Control in Accessibility, then enable system cursor"
            canvas.needsDisplay = true
            openAccessibility()
            return
        }
        cancelTracking("Open your hand to begin system control")
        let screen = window.screen ?? NSScreen.main
        let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        systemPointer.displayBounds = CGDisplayBounds(displayID)
        canvas.systemMode = true
        systemButton.title = "Pause system cursor"
        statusItem?.button?.title = "Hand: LIVE"
        log("SYSTEM_ENABLED display=\(displayID) bounds=\(systemPointer.displayBounds)")
    }

    @objc func pauseSystemCursor() {
        canvas.systemMode = false
        cancelTracking("System cursor paused · test mode")
        systemButton.title = "Enable system cursor"
        statusItem?.button?.title = "Hand: Test"
        log("SYSTEM_PAUSED")
    }

    func applicationWillTerminate(_ notification: Notification) {
        systemPointer.release()
        connection?.cancel(); listener?.cancel()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }

    @objc func toggleScrollPractice(_ button: NSButton) {
        cancelTracking("Open hand to aim · two fingers to scroll")
        canvas.showingPractice.toggle()
        canvas.scrollPractice.isHidden = !canvas.showingPractice
        button.title = canvas.showingPractice ? "Show click targets" : "Scroll practice"
        canvas.needsLayout = true
    }

    @objc func changeMotionMode(_ control: NSPopUpButton) {
        canvas.relativeMode = control.indexOfSelectedItem == 0
        UserDefaults.standard.set(canvas.relativeMode, forKey: "relativePointer")
        cancelTracking("Movement mode changed · open your hand to resume")
    }

    @objc func changeSensitivity(_ slider: NSSlider) {
        canvas.sensitivity = slider.doubleValue
        UserDefaults.standard.set(canvas.sensitivity, forKey: "pointerSensitivity")
        cancelTracking("Sensitivity changed · open your hand to resume")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func accept(_ incoming: NWConnection) {
        // One sensor per test window. Replacement connections reset all gesture state.
        connection?.cancel()
        connection = incoming
        buffer.removeAll(); lastSequence = -1
        rateStart = ProcessInfo.processInfo.systemUptime; rateCount = 0
        cancelTracking("Open your hand to begin")
        incoming.stateUpdateHandler = { [weak self, weak incoming] state in
            guard let self, let incoming, self.connection === incoming else { return }
            self.log("CONNECTION \(state)")
            switch state {
            case .ready:
                self.canvas.connectionText = "iPhone connected"
                self.receive(incoming)
            case .failed, .cancelled:
                if self.canvas.systemMode { self.pauseSystemCursor() }
                self.canvas.connectionText = "iPhone disconnected · waiting to reconnect"
                self.cancelTracking("Connection lost")
                self.connection = nil
            default: break
            }
            self.canvas.needsDisplay = true
        }
        incoming.start(queue: .main)
    }
    func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection, self.connection === connection else { return }
            if let data { self.buffer.append(data) }
            guard self.buffer.count <= 65536 else { connection.cancel(); return }
            while let newline = self.buffer.firstIndex(of: 10) {
                let line = self.buffer.prefix(upTo: newline)
                if let packet = try? JSONDecoder().decode(HandPacket.self, from: line) {
                    self.handle(packet)
                    connection.send(content: Data("\(packet.sequence)\n".utf8), completion: .contentProcessed { _ in })
                }
                else { self.cancelTracking("Invalid input") }
                self.buffer.removeSubrange(...newline)
            }
            if complete || error != nil { connection.cancel() }
            else { self.receive(connection) }
        }
    }
    func cancelTracking(_ reason: String) {
        systemPointer.release()
        pointerMotion.reset(at: canvas.pointer)
        gate.reset(); frozen = nil
        scrollGesture.reset(); canvas.scrollActive = false
        canvas.tracking = false; canvas.pressed = false; canvas.eventText = reason; canvas.needsDisplay = true
    }
    func handle(_ packet: HandPacket) {
        guard packet.version == 1, packet.sequence > lastSequence,
              packet.x.isFinite, packet.y.isFinite, packet.analysisMS.isFinite,
              (0...1).contains(packet.x), (0...1).contains(packet.y) else { cancelTracking("Invalid or out-of-order input"); return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPacket > 0.4 { cancelTracking("Open your hand to begin") }
        let elapsed = now - lastPacket
        lastPacket = now; lastSequence = packet.sequence
        canvas.packets += 1; rateCount += 1
        if now - rateStart >= 2 {
            canvas.rate = Double(rateCount) / max(0.001, now - rateStart)
            rateStart = now; rateCount = 0
            log("STREAM packets=\(canvas.packets) valid=\(packet.valid) pinched=\(packet.pinched) pinchValid=\(packet.canPinch) scrollPose=\(packet.scrollPose ?? false) analysisMS=\(packet.analysisMS)")
        }
        canvas.analysisMS = packet.analysisMS
        guard packet.valid else { cancelTracking("Palm outside view or obscured · return hand to camera"); return }
        // A held click/drag has priority until it is released.
        let wasScrolling = scrollGesture.engaged
        let pose = (packet.scrollPose ?? false) && !packet.pinched && !gate.pressed && !systemPointer.down
        let scrolling = scrollGesture.update(pose: pose, y: 1 - packet.y, elapsed: elapsed)
        if scrolling.consumed {
            gate.reset(); frozen = nil
            systemPointer.release()
            canvas.tracking = true
            canvas.pressed = false
            canvas.scrollActive = scrollGesture.active
            canvas.eventText = canvas.scrollActive ? (pose ? "Scrolling · move hand up/down · open hand to finish" : "Scroll paused · show fist or open hand to finish") : "Fist detected · hold briefly"
            if scrolling.delta != 0 {
                if canvas.systemMode {
                    let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: scrolling.delta, wheel2: 0, wheel3: 0)
                    wheel?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                    wheel?.post(tap: .cghidEventTap)
                } else if canvas.showingPractice {
                    canvas.scrollDocument(by: scrolling.delta)
                } else {
                    canvas.eventText = "Scroll pose detected · open Scroll practice"
                }
                log("SCROLL delta=\(scrolling.delta) system=\(canvas.systemMode)")
            }
            if wasScrolling != scrollGesture.engaged { log("SCROLL_MODE \(scrollGesture.engaged)") }
            pointerMotion.reset(at: canvas.pointer)
            canvas.needsDisplay = true
            return
        }
        canvas.scrollActive = false
        pointerMotion.relative = canvas.relativeMode
        pointerMotion.sensitivity = canvas.sensitivity
        if !canvas.tracking {
            var seed = canvas.pointer
            if canvas.systemMode, let location = CGEvent(source: nil)?.location {
                let bounds = systemPointer.displayBounds
                seed = CGPoint(x: min(1, max(0, (location.x - bounds.minX) / max(1, bounds.width - 1))),
                               y: min(1, max(0, (location.y - bounds.minY) / max(1, bounds.height - 1))))
            }
            pointerMotion.reset(at: seed)
        }
        let point = pointerMotion.update(CGPoint(x: packet.x, y: 1 - packet.y), elapsed: elapsed)
        let event = gate.update(valid: packet.canPinch, pinched: packet.pinched)
        if !packet.canPinch {
            systemPointer.release()
            frozen = nil
        }
        if canvas.systemMode {
            canvas.tracking = true
            canvas.pressed = gate.pressed
            let wasPinching = systemPointer.pinchOrigin != nil
            systemPointer.update(point: point, pinched: packet.canPinch && gate.armed && packet.pinched, event: event, now: now, elapsed: elapsed)
            canvas.pointer = systemPointer.position
            if wasPinching && systemPointer.pinchOrigin == nil && canvas.relativeMode {
                pointerMotion.reset(at: canvas.pointer)
            }
            canvas.eventText = systemPointer.dragging ? "Dragging · release to drop" : (gate.pressed ? "Pinch held · move to drag" : "System cursor active · ⌃⌥⌘P pauses")
            if !packet.canPinch { canvas.eventText = "Palm tracked · fingertips unclear · movement available" }
            if let event, event != "cancel" { log("SYSTEM_\(event.uppercased())") }
            canvas.needsDisplay = true
            return
        }
        if !canvas.tracking { canvas.pointer = point }
        // Freeze aim as soon as the first closed sample arrives, before debouncing.
        if packet.canPinch && packet.pinched && frozen == nil && gate.armed { frozen = canvas.pointer }
        if let frozen { canvas.pointer = frozen }
        else {
            canvas.pointer = point
        }
        canvas.tracking = true
        canvas.pressed = gate.pressed
        if event == "press" { canvas.eventText = "Pinch held · release to click"; log("PRESS") }
        if event == "click" {
            canvas.clicks += 1
            if let target = canvas.target(at: canvas.pointer) {
                canvas.hits[target] += 1
                canvas.eventText = "Clicked target \(target + 1)"
                log("CLICK target=\(target + 1)")
            } else { canvas.misses += 1; canvas.eventText = "Clicked between targets"; log("CLICK miss") }
            frozen = nil
            if canvas.relativeMode { pointerMotion.reset(at: canvas.pointer) }
        } else if !packet.pinched && !gate.pressed {
            if frozen != nil && canvas.relativeMode { pointerMotion.reset(at: canvas.pointer) }
            frozen = nil
            canvas.eventText = gate.armed ? "Ready · pinch to select" : "Hold your hand open"
        }
        if !packet.canPinch { canvas.eventText = "Palm tracked · fingertips unclear · movement available" }
        canvas.needsDisplay = true
    }
}

if CommandLine.arguments.contains("--self-test") {
    testSystemPointer()
    testPointerMotion()
    testScrollGesture()
    assert(isFistScrollPose([0.8, 0.9, nil, nil]))
    assert(isFistScrollPose([nil, 0.9, 0.8, nil]))
    assert(!isFistScrollPose([1.5, 1.5, 1.5, 1.5]))
    assert(!isFistScrollPose([0.8, 1.5, nil, nil])) // pinch, middle open
    assert(!isFistScrollPose([nil, nil, nil, nil]))
    assert(!isFistScrollPose([0.8, nil, nil, nil])) // insufficient entry evidence
    assert(isFistScrollPose([0.8, nil, nil, nil], sustaining: true))
    assert(!allowsPinch([0.8, 0.9, nil, nil]))
    assert(!allowsPinch([nil, nil, nil, nil]))
    assert(allowsPinch([0.8, 1.5, nil, nil]))
    assert(!allowsPinch([0.8, 1.5, 0.8, nil])) // closing hand
    print("PASS fist recognition, partial occlusion, open/pinch rejection and pinch disambiguation")
    let legacyJSON = Data(#"{"version":1,"sequence":1,"valid":true,"x":0.5,"y":0.5,"pinched":false,"analysisMS":20}"#.utf8)
    let legacy = try! JSONDecoder().decode(HandPacket.self, from: legacyJSON)
    assert(legacy.canPinch)
    let palmOnly = HandPacket(sequence: 2, valid: true, x: 0.5, y: 0.5, pinched: false, analysisMS: 20, pinchValid: false)
    assert(palmOnly.valid && !palmOnly.canPinch)
    let receiver = Receiver()
    receiver.canvas.relativeMode = false
    receiver.handle(palmOnly)
    assert(receiver.canvas.tracking && !receiver.gate.armed && !receiver.canvas.pressed)
    print("PASS legacy packets and palm-only movement without click arming")
    // Fist enter/exit never arms a click; pointing must re-arm after the exit.
    for sequence in 3...8 {
        receiver.handle(HandPacket(sequence: sequence, valid: true, x: 0.5, y: 0.5,
            pinched: false, analysisMS: 20, pinchValid: false, scrollPose: true))
    }
    assert(receiver.scrollGesture.active && !receiver.gate.armed && receiver.canvas.clicks == 0)
    for sequence in 9...15 {
        receiver.lastPacket -= 0.08
        receiver.handle(HandPacket(sequence: sequence, valid: true, x: 0.5, y: 0.5,
            pinched: true, analysisMS: 20, pinchValid: true, scrollPose: false))
    }
    assert(!receiver.scrollGesture.engaged && !receiver.gate.pressed && receiver.canvas.clicks == 0)
    print("PASS fist packets and ambiguous exit suppress clicks")
    var gate = PinchGate()
    assert(gate.update(valid: true, pinched: true) == nil)
    assert(gate.update(valid: true, pinched: true) == nil)
    _ = gate.update(valid: true, pinched: false)
    _ = gate.update(valid: true, pinched: false)
    assert(gate.update(valid: true, pinched: true) == nil)
    assert(gate.update(valid: true, pinched: true) == "press")
    assert(gate.update(valid: true, pinched: false) == nil)
    assert(gate.update(valid: true, pinched: false) == "click")
    _ = gate.update(valid: true, pinched: true)
    _ = gate.update(valid: true, pinched: true)
    assert(gate.update(valid: false, pinched: false) == "cancel")
    assert(gate.update(valid: true, pinched: false) == nil)
    assert(gate.update(valid: true, pinched: false) == nil)
    assert(!gate.pressed && gate.armed)
    print("PASS initial closed hand, debounce, one click, dropout cancellation, re-arm")
} else {
    let application = NSApplication.shared
    let delegate = Receiver()
    application.delegate = delegate
    application.run()
}
