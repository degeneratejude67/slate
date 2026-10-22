import SwiftUI

@main
struct SlateApp: App {
    @StateObject private var library = LibraryModel()
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .preferredColorScheme(settings.prefs.theme.colorScheme)
                .onOpenURL { url in library.importExternal(url) }
        }
    }
}
