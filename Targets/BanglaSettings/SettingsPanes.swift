import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BanglaXPC

struct SettingsRoot: View {
    @ObservedObject var model: AppSettingsModel

    var body: some View {
        TabView {
            GeneralPane(model: model).tabItem { Label("General", systemImage: "gearshape") }
            LayoutsPane(model: model).tabItem { Label("Layouts", systemImage: "keyboard") }
            DictionaryPane(model: model).tabItem { Label("Dictionary", systemImage: "text.book.closed") }
            LearningPane(model: model).tabItem { Label("Learning", systemImage: "brain.head.profile") }
            AboutPane(model: model).tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }
}

private struct GeneralPane: View {
    @ObservedObject var model: AppSettingsModel
    var body: some View {
        Form {
            Picker("Active layout", selection: $model.activeLayout) {
                ForEach(model.layouts, id: \.id) { l in Text(l.name).tag(l.id) }
            }
            Stepper("Candidates per panel: \(model.candidateCount)", value: $model.candidateCount, in: 3...9)
            Toggle("Auto-capitalize sentences", isOn: $model.autoCapitalize)
            Toggle("Show Latin hints", isOn: $model.showLatinHints)
            Toggle("Allow usage telemetry", isOn: $model.telemetryOptIn)
        }
        .padding()
    }
}

private struct LayoutsPane: View {
    @ObservedObject var model: AppSettingsModel
    var body: some View {
        VStack(alignment: .leading) {
            Text("Installed layouts")
                .font(.headline)
                .padding(.bottom, 4)
            List(model.layouts, id: \.id) { l in
                HStack {
                    Image(systemName: model.activeLayout == l.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(.tint)
                    Text(l.name)
                    Spacer()
                    if model.activeLayout == l.id { Text("Active").foregroundStyle(.secondary) }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.activeLayout = l.id }
            }
            Text("Fixed layouts map each key to a single glyph; phonetic layouts resolve typed Latin to Bangla.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
    }
}

private struct DictionaryPane: View {
    @ObservedObject var model: AppSettingsModel
    @State private var showImport = false
    var body: some View {
        Form {
            Section("User dictionary") {
                LabeledContent("User words", value: "\(model.userWordCount)")
                LabeledContent("Recorded commits", value: "\(model.commitCount)")
            }
            Section("Import / Export") {
                Button("Import .tsv…") { showImport = true }
                Button("Export .tsv…") { exportTSV() }
            }
            Section("Maintenance") {
                Button("Vacuum database") { model.vacuum() }
                Button("Clear history", role: .destructive) { model.burnHistory() }
            }
            if !model.status.isEmpty {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.tabSeparatedText]) { result in
            if case .success(let url) = result { model.importDictionary(from: url) }
        }
    }

    private func exportTSV() {
        let panel = NSSavePanel()
        panel.title = "Export user dictionary"
        panel.nameFieldStringValue = "bangla-user-dict.tsv"
        panel.allowedContentTypes = [.tabSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportDictionary(to: url)
    }
}

private struct LearningPane: View {
    @ObservedObject var model: AppSettingsModel
    var body: some View {
        Form {
            Section("Adaptive learning") {
                Toggle("Allow usage telemetry", isOn: $model.telemetryOptIn)
                Text("When enabled, the IME records the words you commit to improve ranking and next-word suggestions. Data stays on this machine.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("History") {
                Button("Clear learning history", role: .destructive) { model.burnHistory() }
            }
        }
        .padding()
    }
}

private struct AboutPane: View {
    @ObservedObject var model: AppSettingsModel
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("BanglaIME").font(.title.bold())
            Text("Version \(model.version)").foregroundStyle(.secondary)
            Text("A phonetic and fixed-layout Bangla input method for macOS.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            Text("Bundle: \(BanglaXPCConstants.imeBundleIdentifier)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
    }
}