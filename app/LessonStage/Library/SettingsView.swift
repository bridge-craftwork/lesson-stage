import SwiftUI
import UniformTypeIdentifiers

/// The Settings sheet, reached from the gear in the tab strip. One setting today
/// — the Load-from-Library feature and its knobs — with room to grow.
struct SettingsView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var isChoosingFolder = false
    /// Edited locally and committed on submit / Done, so discovery isn't re-run
    /// against the (possibly iCloud) root on every keystroke.
    @State private var globsDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                librarySection
                if library.enabled {
                    folderSection
                    if library.isConfigured { discoverySection }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitGlobs()
                        dismiss()
                    }
                }
            }
            .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    library.configure(rootURL: url)
                    globsDraft = library.configuration?.ignoreGlobs.joined(separator: ", ") ?? ""
                }
            }
            .onAppear { globsDraft = library.configuration?.ignoreGlobs.joined(separator: ", ") ?? "" }
        }
        .accessibilityIdentifier("settingsSheet")
    }

    private var librarySection: some View {
        Section {
            Toggle("Enable Load from Library", isOn: Binding(
                get: { library.enabled },
                set: { library.setEnabled($0) }
            ))
            .accessibilityIdentifier("enableLibraryToggle")
        } header: {
            Text("Library")
        } footer: {
            Text("Open a class day's handouts as tabs in one tap, from a folder of dated lesson folders.")
        }
    }

    private var folderSection: some View {
        Section("Lesson folder") {
            if let name = library.rootURL?.lastPathComponent {
                LabeledContent("Folder", value: name)
            }
            Button(library.isConfigured ? "Change folder…" : "Choose lesson folder…") {
                isChoosingFolder = true
            }
            .accessibilityIdentifier("chooseFolder")
        }
    }

    private var discoverySection: some View {
        Section {
            Stepper(
                "Days before: \(library.configuration?.windowBefore ?? 0)",
                value: windowBinding(\.windowBefore), in: 0...30
            )
            Stepper(
                "Days ahead: \(library.configuration?.windowAfter ?? 0)",
                value: windowBinding(\.windowAfter), in: 0...30
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Ignore files matching")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("*Zoom*, *sign-in*", text: $globsDraft)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(commitGlobs)
                    .accessibilityIdentifier("ignoreGlobs")
            }
        } header: {
            Text("Discovery")
        } footer: {
            Text("Comma-separated. \u{2018}*\u{2019} matches any run of characters; matching is case-insensitive.")
        }
    }

    private func windowBinding(_ keyPath: WritableKeyPath<LibraryConfiguration, Int>) -> Binding<Int> {
        Binding(
            get: { library.configuration?[keyPath: keyPath] ?? 0 },
            set: { value in library.updateConfiguration { $0[keyPath: keyPath] = value } }
        )
    }

    private func commitGlobs() {
        guard library.isConfigured else { return }
        let globs = globsDraft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard globs != library.configuration?.ignoreGlobs else { return }
        library.updateConfiguration { $0.ignoreGlobs = globs }
    }
}

#Preview {
    SettingsView()
        .environment(LibraryManager())
        .preferredColorScheme(.dark)
}
