import SwiftUI

@main
struct SlateApp: App {
    @StateObject private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .onOpenURL { url in library.importExternal(url) }
        }
    }
}
