import UIKit
import AVFoundation
import Vision
import CoreImage
import Darwin

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ProbeController()
        window?.makeKeyAndVisible()
        return true
    }
}

final class ProbeController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate {
    struct Trial {
        let device: AVCaptureDevice
        let depth: Bool
        var name: String {
            if depth { return "Depth map (grayscale)" }
            if device.deviceType.rawValue.lowercased().contains("infrared") {
                return "Infrared camera"
            }
            return "RGB camera (color)"
        }
    }
    let queue = DispatchQueue(label: "probe.capture")
    lazy var sender = HandSender(queue: queue)
    let networkLabel = UILabel()
    var sending = false
    var sequence = 0
    var pointer: CGPoint?
    var pinchValid = false
    var lastScrollPose = false
    var imageOrientation: CGImagePropertyOrientation = .leftMirrored
    var suppressInputUntil = 0.0
    let rootStack = UIStackView()
    let controlsStack = UIStackView()
    let hint = UILabel()
    var previewHeight: NSLayoutConstraint!
    var previewWidth: NSLayoutConstraint!
    let context = CIContext()
    let preview = UIImageView()
    let status = UILabel()
    let logView = UITextView()
    let modeButton = UIButton(type: .system)
    let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("probe.log")
    var session: AVCaptureSession?
    var trials: [Trial] = []
    var generation = 0
    var current: Trial?
    var frames = 0
    var analyzed = 0
    var hands = 0
    var pinchEligible = 0
    var pinchFrames = 0
    var pinchHeld = false
    var lastPinchStatus = ""
    var started = Date()
    var lastAnalysis = Date.distantPast
    var lastSummary = Date.distantPast
    var logText = ""
    var observers: [NSObjectProtocol] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        status.textColor = .white
        status.numberOfLines = 0
        status.text = "Preparing camera probe…"
        status.font = .systemFont(ofSize: 15, weight: .medium)
        preview.contentMode = .scaleAspectFit
        logView.isEditable = false
        logView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        logView.textColor = .lightGray
        logView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        modeButton.setTitle("Choose stream", for: .normal)
        modeButton.showsMenuAsPrimaryAction = true
        let rerun = UIButton(type: .system)
        rerun.setTitle("Run all", for: .normal)
        rerun.addTarget(self, action: #selector(runAll), for: .touchUpInside)
        let stop = UIButton(type: .system)
        stop.setTitle("Stop", for: .normal)
        stop.addTarget(self, action: #selector(stopCapture), for: .touchUpInside)
        let share = UIButton(type: .system)
        share.setTitle("Share log", for: .normal)
        share.addTarget(self, action: #selector(shareLog), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [modeButton, rerun, stop, share])
        buttons.distribution = .equalSpacing
        hint.text = "Hold a hand 20–50 cm above the front camera. Green dots show confident joints. Each automatic trial lasts 10 seconds."
        hint.numberOfLines = 0
        hint.textColor = .lightGray
        hint.font = .systemFont(ofSize: 13)
        let control = UIButton(type: .system)
        control.setTitle("Start RGB → Mac", for: .normal)
        control.addTarget(self, action: #selector(startMacControl), for: .touchUpInside)
        networkLabel.text = "Mac link stopped"
        networkLabel.textColor = .systemTeal
        networkLabel.font = .systemFont(ofSize: 13)
        networkLabel.numberOfLines = 0
        sender.onStatus = { [weak self] text in
            self?.log("NETWORK \(text)")
            DispatchQueue.main.async { self?.networkLabel.text = text }
        }
        [status, hint, control, networkLabel, buttons, logView].forEach { controlsStack.addArrangedSubview($0) }
        controlsStack.axis = .vertical
        controlsStack.spacing = 6
        rootStack.addArrangedSubview(preview)
        rootStack.addArrangedSubview(controlsStack)
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)
        previewHeight = preview.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.36)
        previewWidth = preview.widthAnchor.constraint(equalTo: rootStack.widthAnchor, multiplier: 0.44)
        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            rootStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            rootStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            rootStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            logView.heightAnchor.constraint(greaterThanOrEqualToConstant: 45)
        ])
        updateLayout(for: view.bounds.size)
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
                let details = String(describing: note.userInfo)
                self?.queue.async { self?.log("SESSION \(name.rawValue) \(details)") }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.stopCapture() })
        AVCaptureDevice.requestAccess(for: .video) { allowed in
            self.queue.async {
                self.log("OS \(UIDevice.current.systemVersion); camera authorized=\(allowed)")
                guard allowed else { return }
                self.discover()
                self.generation += 1
                if ProcessInfo.processInfo.arguments.contains("--mac-control") {
                    self.beginMacControl()
                } else {
                    DispatchQueue.main.async { self.status.text = "Choose a stream, Run all, or Start RGB → Mac" }
                }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateImageOrientation()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        queue.async { self.suppressInputUntil = ProcessInfo.processInfo.systemUptime + 0.8 }
        updateLayout(for: size)
        coordinator.animate(alongsideTransition: nil) { _ in self.updateImageOrientation() }
    }

    func updateLayout(for size: CGSize) {
        let landscape = size.width > size.height
        previewHeight.isActive = false
        previewWidth.isActive = false
        rootStack.axis = landscape ? .horizontal : .vertical
        previewHeight.isActive = !landscape
        previewWidth.isActive = landscape
        hint.isHidden = landscape
        status.font = .systemFont(ofSize: landscape ? 12 : 15, weight: .medium)
    }

    func updateImageOrientation() {
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
        // Interface landscape directions are opposite UIDevice directions.
        let imageOrientation: CGImagePropertyOrientation
        switch orientation {
        case .landscapeLeft: imageOrientation = .upMirrored
        case .landscapeRight: imageOrientation = .downMirrored
        case .portraitUpsideDown: imageOrientation = .rightMirrored
        default: imageOrientation = .leftMirrored
        }
        queue.async {
            guard self.imageOrientation != imageOrientation else { return }
            self.imageOrientation = imageOrientation
            self.pinchHeld = false
            self.suppressInputUntil = ProcessInfo.processInfo.systemUptime + 0.25
            self.log("ORIENTATION interface=\(orientation.rawValue) image=\(imageOrientation.rawValue)")
        }
    }

    func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        print(line, terminator: "")
        fflush(stdout)
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
        logText = String((logText + line).suffix(14000))
        let text = logText
        DispatchQueue.main.async {
            self.logView.text = text
            self.logView.scrollRangeToVisible(NSRange(location: max(0, self.logView.text.utf16.count - 1), length: 1))
        }
    }

    func describe(_ format: AVCaptureDevice.Format) -> String {
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        let bytes: [UInt8] = [24,16,8,0].map { UInt8((subtype >> $0) & 255) }
        let fourCC = String(bytes: bytes, encoding: .ascii) ?? "\(subtype)"
        return "\(dims.width)x\(dims.height) \(fourCC) fps=\(format.videoSupportedFrameRateRanges.map { $0.maxFrameRate })"
    }

    func discover() {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera, .builtInTrueDepthCamera, .builtInLiDARDepthCamera]
        for symbol in ["AVCaptureDeviceTypeBuiltInInfraredMetadataCamera", "AVCaptureDeviceTypeBuiltInColorAssistedInfraredMetadataCamera"] {
            if let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol) {
                let value = address.assumingMemoryBound(to: NSString?.self).pointee
                log("SYMBOL \(symbol)=\(value ?? "nil")")
                if let value { types.append(AVCaptureDevice.DeviceType(rawValue: value as String)) }
            } else { log("SYMBOL unavailable \(symbol)") }
        }
        var devices: [String: AVCaptureDevice] = [:]
        for type in types {
            let found = AVCaptureDevice.DiscoverySession(deviceTypes: [type], mediaType: nil, position: .unspecified).devices
            log("DISCOVERY \(type.rawValue) count=\(found.count)")
            for device in found {
                devices[device.uniqueID] = device
                for child in device.constituentDevices { devices[child.uniqueID] = child }
            }
        }
        for device in devices.values.sorted(by: { $0.uniqueID < $1.uniqueID }) {
            log("DEVICE \(device.deviceType.rawValue) \(device.localizedName) id=\(device.uniqueID) position=\(device.position.rawValue) constituents=\(device.constituentDevices.map { $0.deviceType.rawValue })")
            for (index, format) in device.formats.enumerated() {
                log("FORMAT \(index) \(describe(format)) depth=[\(format.supportedDepthDataFormats.map { describe($0) }.joined(separator: "; "))]")
            }
        }
        if let front = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) {
            trials.append(Trial(device: front, depth: false))
            trials.append(Trial(device: front, depth: true))
        }
        for device in devices.values.sorted(by: { $0.uniqueID < $1.uniqueID }) where device.deviceType.rawValue.lowercased().contains("infrared") {
            trials.append(Trial(device: device, depth: false))
        }
        let choices = trials
        DispatchQueue.main.async {
            self.modeButton.menu = UIMenu(children: choices.map { trial in
                UIAction(title: trial.name) { _ in
                    self.queue.async { self.generation += 1; self.start(trial) }
                }
            })
        }
        log("TRIALS \(trials.map { $0.name })")
    }

    @objc func startMacControl() { queue.async { self.beginMacControl() } }
    func beginMacControl() {
        generation += 1
        guard let rgb = trials.first(where: { !$0.depth && $0.device.deviceType == .builtInTrueDepthCamera }) else { return }
        sending = true
        sender.start()
        start(rgb)
    }

    @objc func runAll() {
        queue.async { self.generation += 1; self.run(index: 0, token: self.generation) }
    }
    @objc func stopCapture() {
        queue.async {
            self.generation += 1
            self.sending = false
            self.sender.stop()
            self.summary()
            self.session?.stopRunning()
            self.session = nil
            DispatchQueue.main.async { self.status.text = "Capture stopped"; UIApplication.shared.isIdleTimerDisabled = false }
        }
    }
    @objc func shareLog() {
        let sheet = UIActivityViewController(activityItems: [logURL], applicationActivities: nil)
        present(sheet, animated: true)
    }
    func run(index: Int, token: Int) {
        guard token == generation else { return }
        guard index < trials.count else {
            summary()
            log("AUTOMATIC TRIALS COMPLETE. Leaving public depth preview active for manual testing.")
            if let trial = trials.first(where: { $0.depth }) { start(trial) }
            return
        }
        start(trials[index])
        queue.asyncAfter(deadline: .now() + 10) { self.run(index: index + 1, token: token) }
    }
    func summary() {
        guard let current else { return }
        let duration = Date().timeIntervalSince(started)
        log("SUMMARY \(current.name) elapsed=\(String(format: "%.1f", duration)) frames=\(frames) fps=\(String(format: "%.1f", Double(frames) / max(duration, 0.001))) analyzed=\(analyzed) framesWithHands=\(hands) pinchEligible=\(pinchEligible) pinchFrames=\(pinchFrames)")
    }
    func start(_ trial: Trial) {
        sender.send(HandPacket(sequence: sequence, valid: false, x: 0, y: 0, pinched: false, analysisMS: 0))
        sequence += 1
        summary()
        session?.stopRunning()
        session = nil
        current = trial
        frames = 0; analyzed = 0; hands = 0
        pinchEligible = 0; pinchFrames = 0; pinchHeld = false; lastPinchStatus = ""; lastScrollPose = false
        started = Date(); lastAnalysis = .distantPast; lastSummary = Date()
        log("START \(trial.name) deviceType=\(trial.device.deviceType.rawValue)")
        DispatchQueue.main.async { self.status.text = trial.name; self.preview.image = nil; UIApplication.shared.isIdleTimerDisabled = true }
        let capture = AVCaptureSession()
        do {
            let input = try AVCaptureDeviceInput(device: trial.device)
            capture.beginConfiguration()
            capture.sessionPreset = .inputPriority
            guard capture.canAddInput(input) else {
                capture.commitConfiguration(); log("FAIL cannot add input"); return
            }
            capture.addInput(input)
            try trial.device.lockForConfiguration()
            let formats = trial.device.formats.filter { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dimensions.width <= 1280 && (!trial.depth || !format.supportedDepthDataFormats.isEmpty)
            }
            if let format = formats.max(by: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }) {
                trial.device.activeFormat = format
            }
            if trial.depth {
                let formats = trial.device.activeFormat.supportedDepthDataFormats
                if let depthFormat = formats.filter({ CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32 }).max(by: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }) {
                    trial.device.activeDepthDataFormat = depthFormat
                }
            }
            trial.device.unlockForConfiguration()
            log("ACTIVE \(describe(trial.device.activeFormat)) depth=\(trial.device.activeDepthDataFormat.map { describe($0) } ?? "none")")
            if trial.depth {
                let output = AVCaptureDepthDataOutput()
                output.isFilteringEnabled = false
                output.setDelegate(self, callbackQueue: queue)
                guard capture.canAddOutput(output) else { capture.commitConfiguration(); log("FAIL cannot add depth output"); return }
                capture.addOutput(output)
            } else {
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: queue)
                guard capture.canAddOutput(output) else { capture.commitConfiguration(); log("FAIL cannot add video output"); return }
                capture.addOutput(output)
            }
            capture.commitConfiguration()
            session = capture
            capture.startRunning()
            log("RUNNING \(capture.isRunning)")
        } catch { log("FAIL \(error)") }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        process(buffer)
    }
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        let depth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32).depthDataMap
        let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
        var gray: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &gray) == kCVReturnSuccess, let gray else { return }
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        CVPixelBufferLockBaseAddress(gray, [])
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly); CVPixelBufferUnlockBaseAddress(gray, []) }
        let source = CVPixelBufferGetBaseAddress(depth)!
        let destination = CVPixelBufferGetBaseAddress(gray)!
        for y in 0..<height {
            let input = source.advanced(by: y * CVPixelBufferGetBytesPerRow(depth)).assumingMemoryBound(to: Float.self)
            let pixels = destination.advanced(by: y * CVPixelBufferGetBytesPerRow(gray)).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let meters = input[x]
                let shade: UInt8 = meters.isFinite && meters > 0 ? UInt8(max(0, min(255, (0.8 - meters) / 0.65 * 255))) : 0
                pixels[x * 4] = shade; pixels[x * 4 + 1] = shade; pixels[x * 4 + 2] = shade; pixels[x * 4 + 3] = 255
            }
        }
        process(gray)
    }
    // Diagnostic only. Missing joints explicitly invalidate the pinch estimate.
    // The thresholds are initial hypotheses and require per-user calibration.
    func measurePinch(_ observations: [VNHumanHandPoseObservation], size: CGSize) -> String {
        pointer = nil
        pinchValid = false
        if let observation = observations.first,
           let middle = try? observation.recognizedPoint(.middleMCP), middle.confidence > 0.3 {
            pointer = middle.location
        }
        var state = "Pinch unknown — thumb/index or palm tracking lost"
        if let observation = observations.first,
           let thumb = try? observation.recognizedPoint(.thumbTip),
           let index = try? observation.recognizedPoint(.indexTip),
           let wrist = try? observation.recognizedPoint(.wrist),
           let middle = try? observation.recognizedPoint(.middleMCP),
           [thumb, index, wrist, middle].allSatisfy({ $0.confidence > 0.3 }) {
            func distance(_ a: VNRecognizedPoint, _ b: VNRecognizedPoint) -> CGFloat {
                hypot((a.location.x - b.location.x) * size.width, (a.location.y - b.location.y) * size.height)
            }
            let palm = distance(wrist, middle)
            if palm > 10 {
                pinchValid = true
                pinchEligible += 1
                let ratio = distance(thumb, index) / palm
                pinchHeld = ratio < (pinchHeld ? 0.40 : 0.25)
                if pinchHeld { pinchFrames += 1 }
                state = "\(pinchHeld ? "Pinch candidate" : "Open") · tip gap / palm \(String(format: "%.2f", ratio))"
            } else { pinchHeld = false }
        } else { pinchHeld = false }
        let category = String(state.split(separator: "·")[0]).trimmingCharacters(in: .whitespaces)
        if category != lastPinchStatus {
            log("PINCH \(state)")
            lastPinchStatus = category
        }
        return state
    }

    func fingerCurlRatios(_ observation: VNHumanHandPoseObservation?, size: CGSize) -> [Double?] {
        let unknown: [Double?] = [nil, nil, nil, nil]
        guard let observation,
              let wrist = try? observation.recognizedPoint(.wrist), wrist.confidence > 0.25 else { return unknown }
        func distance(_ a: VNRecognizedPoint, _ b: VNRecognizedPoint) -> Double {
            Double(hypot((a.location.x - b.location.x) * size.width, (a.location.y - b.location.y) * size.height))
        }
        let joints: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.indexTip, .indexPIP), (.middleTip, .middlePIP), (.ringTip, .ringPIP), (.littleTip, .littlePIP)
        ]
        return joints.map { tipName, pipName -> Double? in
            guard let tip = try? observation.recognizedPoint(tipName),
                  let pip = try? observation.recognizedPoint(pipName),
                  tip.confidence > 0.25, pip.confidence > 0.25 else { return nil }
            let base = distance(pip, wrist)
            return base > 10 ? distance(tip, wrist) / base : nil
        }
    }

    func process(_ buffer: CVPixelBuffer) {
        frames += 1
        if frames == 1 { log("FIRST FRAME \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer)) pixelType=\(CVPixelBufferGetPixelFormatType(buffer))") }
        if Date().timeIntervalSince(lastSummary) > 5 { summary(); lastSummary = Date() }
        guard Date().timeIntervalSince(lastAnalysis) >= (sending ? 0.05 : 0.1) else { return }
        lastAnalysis = Date()
        let analysisStart = ProcessInfo.processInfo.systemUptime
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: imageOrientation).perform([request])
            analyzed += 1
            let observations = request.results ?? []
            let points = observations.flatMap { observation -> [VNRecognizedPoint] in
                guard let points = try? observation.recognizedPoints(.all) else { return [] }
                return points.values.filter { $0.confidence > 0.3 }
            }
            if points.count >= 5 { hands += 1 }
            let image = CIImage(cvPixelBuffer: buffer).oriented(imageOrientation)
            guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
            let size = CGSize(width: cgImage.width, height: cgImage.height)
            var pinchStatus = measurePinch(observations, size: size)
            let ratios = fingerCurlRatios(observations.first, size: size)
            let scrollPose = isFistScrollPose(ratios, sustaining: lastScrollPose)
            // A fist may put thumb/index tips close together. It must not be
            // sent as a pinch, including during ambiguous pose transitions.
            if scrollPose || !allowsPinch(ratios) {
                pinchValid = false
                pinchHeld = false
                pinchStatus = "Pinch disabled · fingers curled or unclear"
            }
            if scrollPose != lastScrollPose {
                log("SCROLL_POSE \(scrollPose)")
                lastScrollPose = scrollPose
            }
            if sending {
                sequence += 1
                let orientationStable = ProcessInfo.processInfo.systemUptime >= suppressInputUntil
                sender.send(HandPacket(sequence: sequence, valid: pointer != nil && orientationStable,
                    x: Double(pointer?.x ?? 0), y: Double(pointer?.y ?? 0), pinched: pinchHeld,
                    analysisMS: (ProcessInfo.processInfo.systemUptime - analysisStart) * 1000,
                    pinchValid: pinchValid && orientationStable, scrollPose: scrollPose && orientationStable))
            }
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let rendered = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
                UIColor.green.setFill()
                for point in points {
                    renderer.cgContext.fillEllipse(in: CGRect(x: point.location.x * size.width - 4, y: (1 - point.location.y) * size.height - 4, width: 8, height: 8))
                }
            }
            let label = "\(current?.name ?? "")\n\(frames) frames · \(points.count) joints · \(hands)/\(analyzed) hand detections\n\(scrollPose ? "Fist scroll pose" : (pointer == nil ? "Palm lost" : "Palm tracked")) · \(pinchStatus)"
            DispatchQueue.main.async { self.preview.image = rendered; self.status.text = label }
        } catch {
            if analyzed == 0 { log("VISION ERROR \(error)") }
            analyzed += 1
        }
    }
}
