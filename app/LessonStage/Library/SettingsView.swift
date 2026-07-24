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
    @State private var leafDraft = ""

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
                        commitLeaf()
                        dismiss()
                    }
                }
            }
            .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    library.configure(rootURL: url)
                    syncDrafts()
                }
            }
            .onAppear(perform: syncDrafts)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Handouts subfolder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Handouts", text: $leafDraft)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(commitLeaf)
                    .accessibilityIdentifier("leafSubfolder")
            }
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
            Text("The subfolder inside each day's folder that holds the handouts — leave empty if the PDFs sit directly in the day folder. Ignore globs are comma-separated; \u{2018}*\u{2019} matches any run of characters, case-insensitively.")
        }
    }

    private func windowBinding(_ keyPath: WritableKeyPath<LibraryConfiguration, Int>) -> Binding<Int> {
        Binding(
            get: { library.configuration?[keyPath: keyPath] ?? 0 },
            set: { value in library.updateConfiguration { $0[keyPath: keyPath] = value } }
        )
    }

    private func syncDrafts() {
        globsDraft = library.configuration?.ignoreGlobs.joined(separator: ", ") ?? ""
        leafDraft = library.configuration?.leafSubfolder ?? ""
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

    private func commitLeaf() {
        guard library.isConfigured else { return }
        let leaf = leafDraft.trimmingCharacters(in: .whitespaces)
        guard leaf != library.configuration?.leafSubfolder else { return }
        library.updateConfiguration { $0.leafSubfolder = leaf }
    }
}

#Preview {
    SettingsView()
        .environment(LibraryManager())
        .preferredColorScheme(.dark)
}
