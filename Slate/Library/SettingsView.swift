import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.prefs.theme) {
                    ForEach(ThemeChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Desk colour", selection: $settings.prefs.desk) {
                    ForEach(DeskColor.allCases) { Text($0.label).tag($0) }
                }
                Picker("Library cover size", selection: $settings.prefs.gridDensity) {
                    ForEach(GridDensity.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                Picker("Toolbar", selection: $settings.prefs.toolbar) {
                    ForEach(ToolbarPlacement.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Page scrolling", selection: $settings.prefs.scroll) {
                    ForEach(ScrollAxis.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("scroll-picker")
                Toggle("Draw with finger", isOn: $settings.prefs.fingerDraws)
                Toggle("Two-finger tap to undo, three to redo", isOn: $settings.prefs.twoFingerUndo)
                Toggle("Add a page when writing on the last one", isOn: $settings.prefs.autoAddPage)
                Toggle("Show page number", isOn: $settings.prefs.showPageNumber)
            } header: {
                Text("Writing")
            } footer: {
                Text("With finger drawing off, the Pencil writes and fingers scroll and zoom, so your palm never leaves marks.")
            }

            Section("New Notebooks") {
                LabeledContent("Paper", value: settings.prefs.defaultPaper.label)
                Picker("Paper colour", selection: $settings.prefs.defaultPaper.tone) {
                    ForEach(PaperTone.allCases) { Text($0.label).tag($0) }
                }
                Picker("Page size", selection: $settings.prefs.defaultSize) {
                    ForEach(PageSizePreset.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Cover", value: settings.prefs.defaultCover.label)
                Text("Change the default paper and cover in Marketplace.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Notebooks", value: "On My iPad › Slate › Library")
                LabeledContent("Templates", value: "On My iPad › Slate › Templates")
                if let expiry = Provisioning.expiry {
                    LabeledContent("Signature ends", value: expiry.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            } header: {
                Text("Storage and App")
            } footer: {
                Text("Notebooks are plain folders you can see in the Files app. Re-signing with iloader keeps them.")
            }
        }
        .navigationTitle("Settings")
    }
}
