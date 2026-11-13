import AppKit
import GlanceCore

enum AppError: LocalizedError {
    case missingKey(String)
    case noScreen

    var errorDescription: String? {
        switch self {
        case .missingKey(let service): return "Add an API key for \(service) in the menu bar."
        case .noScreen: return "Couldn't find a screen to capture."
        }
    }
}

/// Owns the app's state and wires hotkeys, capture, the AI call and the overlay together.
@MainActor
final class AppController: ObservableObject {
    let settings = Settings()

    @Published private(set) var model = OverlayModel()
    @Published private(set) var lastAnswer: String?
    @Published private(set) var lastInfo = ""
    @Published private(set) var testLines: [String] = []
    @Published private(set) var isTesting = false
    @Published private(set) var fetchedModels: [String] = []
    @Published private(set) var shortcutMessage: String?
    @Published private(set) var hasScreenPermission = CGPreflightScreenCaptureAccess()

    private let overlay = OverlayController()
    private var task: Task<Void, Never>?
    /// The display the current answer belongs to, and its dot (if any).
    private var activeDisplayID: CGDirectDisplayID?
    private var activeDot: DotPlacement?

    private static let captureHotKeyID: UInt32 = 1
    private static let toggleHotKeyID: UInt32 = 2

    // MARK: Lifecycle

    func start() {
        registerShortcuts()
    }

    func registerShortcuts() {
        let captureOK = HotKeyCenter.shared.register(id: Self.captureHotKeyID, combo: settings.captureCombo) { [weak self] in
            MainActor.assumeIsolated { self?.newCapture() }
        }
        let toggleOK = HotKeyCenter.shared.register(id: Self.toggleHotKeyID, combo: settings.toggleCombo) { [weak self] in
            MainActor.assumeIsolated { self?.toggleAnswers() }
        }
        shortcutMessage = (captureOK && toggleOK)
            ? nil
            : "One of these shortcuts is already taken by another app. Pick a different one."
    }

    /// Stops the shortcuts while the user is recording a new one.
    func pauseShortcuts() {
        HotKeyCenter.shared.unregisterAll()
    }

    // MARK: Hotkey 1: new capture

    /// Throws the old answer away at once, then captures and asks again.
    /// Whether the result is drawn is up to the switch.
    func newCapture() {
        task?.cancel()
        let id = model.beginCapture()
        activeDot = nil
        render()

        guard let screen = NSScreen.underMouse, let displayID = screen.displayID else {
            model.fail(id: id, message: AppError.noScreen.localizedDescription)
            render()
            return
        }
        activeDisplayID = displayID
        task = Task { [weak self] in
            await self?.run(id: id, displayID: displayID)
        }
    }

    private func run(id: Int, displayID: CGDirectDisplayID) async {
        let preset = settings.preset
        let config = settings.serviceConfig
        let key = settings.apiKey(for: preset.id)
        let instructions = settings.instructions
        let timeout = settings.cloudTimeout
        let snapToText = settings.snapToText
        let started = Date()

        do {
            let shot = try await CaptureService.capture(displayID: displayID, maxLongEdge: settings.imageLongEdge)
            hasScreenPermission = true
            guard !Task.isCancelled, model.captured(id: id) else { return }
            render()

            guard !key.isEmpty else { throw AppError.missingKey(preset.name) }

            // Read the on-screen text at the same time as the AI call, so it
            // adds no waiting.
            let image = shot.image
            var ocr: Task<[TextBox], Never>?
            if snapToText {
                ocr = Task.detached(priority: .userInitiated) { TextRecognizer.boxes(in: image) }
            }

            let client = CloudClient(config: config, apiKey: key)
            let jpeg = shot.jpegBase64
            let (reply, source) = try await runHedged(
                cloud: { try await client.analyze(jpegBase64: jpeg, instructions: instructions) },
                local: nil, // The local backup model plugs in here later.
                policy: HedgePolicy(cloudTimeout: timeout, hedgeDelay: 1.5, localTimeout: 30)
            )

            let answer = AnswerParser.parse(reply.text)
            var dot: DotPlacement?
            if let target = answer.target {
                var point = CGPoint(x: target.x, y: target.y)
                var snapped = false
                if let ocr {
                    let result = TextSnap.snap(target, boxes: await ocr.value, aspect: shot.aspect)
                    point = result.point
                    snapped = result.snapped
                }
                let brightness = ImageTools.brightness(of: image, around: point) ?? 0.5
                dot = DotPlacement(normalized: point, darkTone: brightness > 0.5, snapped: snapped)
            }

            guard !Task.isCancelled, model.finish(id: id, answer: answer) else { return }
            activeDot = dot
            lastAnswer = answer.text
            var info = "\(reply.model) · " + String(format: "%.1f s", Date().timeIntervalSince(started))
            if reply.usedBackup { info += " · main model was busy" }
            if source == .local { info += " · answered on this Mac" }
            if dot?.snapped == true { info += " · dot snapped to text" }
            lastInfo = info
            render()
        } catch {
            guard !Task.isCancelled else { return }
            if case CaptureError.noPermission = error { hasScreenPermission = false }
            if model.fail(id: id, message: Self.describe(error, timeout: timeout)) {
                render()
            }
        }
    }

    // MARK: Hotkey 2: the switch

    func toggleAnswers() {
        model.toggleSwitch()
        render()
    }

    func setAnswersVisible(_ on: Bool) {
        model.setSwitch(on)
        render()
    }

    // MARK: Drawing

    private func render() {
        let screen = activeDisplayID.flatMap(NSScreen.withDisplayID) ?? NSScreen.underMouse
        switch model.visible {
        case .nothing:
            overlay.hideAll()
        case .working:
            overlay.hideDot()
            if settings.showWorking {
                overlay.showBubble(.working, on: screen, corner: settings.corner)
            } else {
                overlay.hideBubble()
            }
        case .error(let message):
            overlay.hideDot()
            overlay.showBubble(.error(message), on: screen, corner: settings.corner)
        case .answer(let answer):
            overlay.showBubble(.answer(answer.text), on: screen, corner: settings.corner)
            if settings.showDot, let dot = activeDot, let screen {
                overlay.showDot(dot, on: screen, opacity: settings.effectiveDotOpacity, diameter: settings.dotSize)
            } else {
                overlay.hideDot()
            }
        }
    }

    /// Shows the dot in the middle of the screen for a moment, to tune how faint it is.
    func previewDot() {
        guard let screen = NSScreen.underMouse else { return }
        let darkTone = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) != .darkAqua
        let dot = DotPlacement(normalized: CGPoint(x: 0.5, y: 0.5), darkTone: darkTone, snapped: false)
        overlay.showDot(dot, on: screen, opacity: settings.effectiveDotOpacity, diameter: settings.dotSize)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self?.render()
        }
    }

    // MARK: Menu actions

    var statusLine: String {
        let base: String
        switch model.phase {
        case .empty: base = "Press \(settings.captureCombo.displayString) to look at your screen."
        case .capturing, .working: base = "Looking…"
        case .ready: base = lastInfo
        case .failed(_, let message): base = message
        }
        return model.switchOn ? base : base + " (answers hidden)"
    }

    func copyLastAnswer() {
        guard let lastAnswer else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastAnswer, forType: .string)
    }

    func refreshPermission() {
        hasScreenPermission = CGPreflightScreenCaptureAccess()
    }

    func requestScreenPermission() {
        _ = CGRequestScreenCaptureAccess()
        refreshPermission()
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// macOS often only applies a new Screen Recording permission after a restart.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }

    func fetchModels() {
        let config = settings.serviceConfig
        let key = settings.apiKey(for: settings.presetID)
        guard !key.isEmpty else {
            testLines = ["Save an API key first."]
            return
        }
        Task {
            do {
                let models = try await CloudClient(config: config, apiKey: key).listModels()
                fetchedModels = models
                testLines = models.isEmpty ? ["The service didn't list any models."] : []
            } catch {
                testLines = ["Couldn't list models: \(Self.describe(error, timeout: 30))"]
            }
        }
    }

    func testCurrentService() {
        runSpeedTests([settings.preset])
    }

    func testAllServices() {
        runSpeedTests(ServicePresets.all.filter { settings.hasKey($0.id) })
    }

    /// Sends a tiny image to each service and times the round trip, so you can
    /// pick the fastest one for your network.
    private func runSpeedTests(_ presets: [ServicePreset]) {
        guard !isTesting else { return }
        guard !presets.isEmpty else {
            testLines = ["No saved API keys yet."]
            return
        }
        isTesting = true
        testLines = []
        Task {
            for preset in presets {
                let config = settings.serviceConfig(for: preset.id)
                let key = settings.apiKey(for: preset.id)
                guard !key.isEmpty else {
                    testLines.append("\(preset.name): no key saved")
                    continue
                }
                let client = CloudClient(config: config, apiKey: key)
                let started = Date()
                do {
                    let reply = try await withTimeout(seconds: 30) {
                        try await client.analyze(
                            jpegBase64: ImageTools.testImageBase64,
                            instructions: "This is a connection test. Set text to \"ok\" and has_target to false."
                        )
                    }
                    var line = "\(preset.name), \(reply.model): " + String(format: "%.1f s", Date().timeIntervalSince(started))
                    if reply.usedBackup { line += " (main model busy, backup answered)" }
                    testLines.append(line)
                } catch {
                    testLines.append("\(preset.name): failed. \(Self.describe(error, timeout: 30))")
                }
            }
            isTesting = false
        }
    }

    static func describe(_ error: Error, timeout: Double) -> String {
        if error is TimeoutError {
            return "The AI service didn't answer within \(Int(timeout)) seconds."
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "You seem to be offline."
            case .timedOut:
                return "The AI service took too long to answer."
            case .cannotFindHost, .cannotConnectToHost:
                return "Couldn't reach the AI service. Check its address in the menu bar."
            default:
                return urlError.localizedDescription
            }
        }
        if let described = (error as? LocalizedError)?.errorDescription {
            return described
        }
        return error.localizedDescription
    }
}
