import SwiftUI

enum V2Theme {
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let secondary = Color(red: 0.34, green: 0.37, blue: 0.42)
    static let tertiary = Color(red: 0.58, green: 0.61, blue: 0.66)
    static let page = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let panel = Color.white
    static let line = Color(red: 0.86, green: 0.88, blue: 0.91)
    static let blue = Color(red: 0.10, green: 0.40, blue: 0.88)
    static let mint = Color(red: 0.08, green: 0.62, blue: 0.50)
    static let orange = Color(red: 0.92, green: 0.45, blue: 0.18)
    static let violet = Color(red: 0.45, green: 0.34, blue: 0.78)

    static func goalColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "blue", "writing", "career":
            blue
        case "mint", "teal", "health":
            mint
        case "orange", "commitment", "admin":
            orange
        case "violet", "growth", "learning":
            violet
        default:
            secondary
        }
    }
}

extension View {
    func v2ScreenBackground() -> some View {
        background(V2Theme.page.ignoresSafeArea())
    }
}
