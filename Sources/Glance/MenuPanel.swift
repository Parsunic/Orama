import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import GlanceCore

/// Everything you can change, in the panel that drops down from the menu bar icon.
struct MenuPanel: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: Settings
    @State private var keyDraft = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !controller.hasScreenPermission { permissionBox }
                    serviceSection
                    instructionsSection
                    displaySection
                    shortcutsSection
                    Toggle("Open Glance when I log in", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                }
                .padding(14)
            }
            // A fixed height: inside a menu bar panel, a scroll area with only a
            // maximum height collapses to nothing.
            .frame(height: 520)
            Divider()
            HStack {
                Spacer()
                Button("Quit Glance") { NSApp.terminate(nil) }
            }
            .padding(10)
        }
        .frame(width: 390)
        .onAppear { controller.refreshPermission() }
        .onChange(of: settings.presetID) { _, _ in keyDraft = "" }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Glance").font(.headline)
                Spacer()
                Toggle("Show answers", isOn: Binding(
                    get: { controller.model.switchOn },
                    set: { controller.setAnswersVisible($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            Text(controller.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack {
                Button("New capture (\(settings.captureCombo.displayString))") { controller.newCapture() }
                Button("Copy answer") { controller.copyLastAnswer() }
                    .disabled(controller.lastAnswer == nil)
            }
            .controlSize(.small)
        }
        .padding(14)
    }

    private var permissionBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Glance needs permission to see your screen", systemImage: "lock")
                .font(.callout.weight(.medium))
            Text("Turn Glance on under Screen & System Audio Recording, then reopen it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Ask for permission") { controller.requestScreenPermission() }
                Button("Open System Settings") { controller.openScreenRecordingSettings() }
                Button("Reopen Glance") { controller.relaunch() }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private var serviceSection: some View {
        SectionBox("AI service") {
            Picker("Service", selection: $settings.presetID) {
                ForEach(ServicePresets.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .labelsHidden()
            Text(settings.preset.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            FieldRow("Address") {
                TextField("https://…", text: $settings.baseURL)
                    .textFieldStyle(.roundedBorder)
            }
            FieldRow("Model") {
                HStack(spacing: 6) {
                    TextField("model name", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                    Menu("List") {
                        if controller.fetchedModels.isEmpty {
                            Button("Fetch models from the service") { controller.fetchModels() }
                        } else {
                            ForEach(controller.fetchedModels, id: \.self) { name in
                                Button(name) { settings.model = name }
                            }
                            Divider()
                            Button("Refresh list") { controller.fetchModels() }
                        }
                    }
                    .fixedSize()
                }
            }
            FieldRow("API key") {
                HStack(spacing: 6) {
                    SecureField(settings.hasKey(settings.presetID) ? "Saved. Paste to replace" : "Paste your key", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        settings.saveAPIKey(keyDraft, for: settings.presetID)
                        keyDraft = ""
                    }
                    .disabled(keyDraft.isEmpty)
                }
            }
            FieldRow("Thinking") {
                TextField(settings.preset.format == .anthropic ? "low" : "service default", text: $settings.reasoningEffort)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Give up after")
                Slider(value: $settings.cloudTimeout, in: 3...30, step: 1)
                Text("\(Int(settings.cloudTimeout)) s").monospacedDigit().frame(width: 34, alignment: .trailing)
            }
            HStack {
                Button("Test speed") { controller.testCurrentService() }
                Button("Compare all saved services") { controller.testAllServices() }
                if controller.isTesting { ProgressView().controlSize(.small) }
            }
            .controlSize(.small)
            ForEach(Array(controller.testLines.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Reset this service to its defaults") { settings.resetService() }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private var instructionsSection: some View {
        SectionBox("What to ask about the screen") {
            TextEditor(text: $settings.instructions)
                .font(.system(size: 12))
                .frame(height: 76)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            Button("Reset to the default question") { settings.instructions = Prompt.defaultInstructions }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private var displaySection: some View {
        SectionBox("Screen and display") {
            Picker("Picture sent", selection: $settings.imageLongEdge) {
                Text("Fastest").tag(1024)
                Text("Balanced").tag(1280)
                Text("Sharpest").tag(1600)
            }
            .pickerStyle(.segmented)
            Text("Smaller pictures upload faster. Sharper helps when the text on screen is tiny.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Show a faint dot on the spot it's talking about", isOn: $settings.showDot)
            Toggle("Snap the dot onto matching text on screen", isOn: $settings.snapToText)
                .disabled(!settings.showDot)
            HStack {
                Text("Dot strength")
                Slider(value: $settings.dotOpacity, in: 0.03...0.4)
                Text(verbatim: "\(Int(settings.dotOpacity * 100))%").monospacedDigit().frame(width: 34, alignment: .trailing)
            }
            .disabled(!settings.showDot)
            HStack {
                Text("Dot size")
                Slider(value: $settings.dotSize, in: 16...96)
                Button("Preview") { controller.previewDot() }.controlSize(.small)
            }
            .disabled(!settings.showDot)

            Toggle("Show “Looking…” while waiting", isOn: $settings.showWorking)
            Picker("Answer box", selection: $settings.corner) {
                ForEach(Corner.allCases, id: \.self) { corner in
                    Text(corner.title).tag(corner)
                }
            }
        }
    }

    private var shortcutsSection: some View {
        SectionBox("Shortcuts") {
            ShortcutRecorder(
                title: "New capture",
                combo: $settings.captureCombo,
                onBegin: { controller.pauseShortcuts() },
                onEnd: { controller.registerShortcuts() }
            )
            ShortcutRecorder(
                title: "Show / hide answers",
                combo: $settings.toggleCombo,
                onBegin: { controller.pauseShortcuts() },
                onEnd: { controller.registerShortcuts() }
            )
            if let message = controller.shortcutMessage {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Small building blocks

private struct SectionBox<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct FieldRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label).frame(width: 64, alignment: .leading)
            content
        }
    }
}

/// Click the button, then press the new shortcut. Esc cancels. The existing
/// shortcuts are switched off while recording so they don't fire instead.
@MainActor
struct ShortcutRecorder: View {
    let title: String
    @Binding var combo: KeyCombo
    let onBegin: () -> Void
    let onEnd: () -> Void

    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Button(recording ? "Press keys…" : combo.displayString) {
                    if recording { stop() } else { start() }
                }
                .frame(minWidth: 110)
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func start() {
        onBegin()
        recording = true
        hint = "Hold ⌘ or ⌃ (plus any others) and press a key. Esc cancels."
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors run on the main thread.
            let consumed = MainActor.assumeIsolated { handle(event) }
            return consumed ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard recording else { return false }
        if event.keyCode == UInt16(kVK_Escape) {
            stop()
            return true
        }
        let candidate = KeyCombo(event: event)
        guard candidate.hasRequiredModifier else {
            hint = "Include ⌘ or ⌃ so the shortcut doesn't clash with normal typing."
            return true
        }
        combo = candidate
        stop()
        return true
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        hint = nil
        onEnd()
    }
}
