import SwiftUI
import UIKit

enum Theme {
    /// The grey desk around the pages, as in GoodNotes.
    static let desk = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.11, alpha: 1)
            : UIColor(red: 0.894, green: 0.898, blue: 0.910, alpha: 1)
    }
    static let accent = Color(red: 0.20, green: 0.42, blue: 0.85)
}
