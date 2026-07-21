import SwiftUI

enum V2Theme {
    enum ColorRole {
        // Option 2: subtly warm paper neutrals without turning the app into a notebook.
        static let canvas = Color(red: 0.982, green: 0.976, blue: 0.960)
        static let surface = Color.white
        static let surfaceRaised = Color(red: 0.998, green: 0.996, blue: 0.990)
        static let surfaceMuted = Color(red: 0.955, green: 0.949, blue: 0.934)
        static let outline = Color(red: 0.885, green: 0.878, blue: 0.862)

        static let textPrimary = Color(red: 0.055, green: 0.060, blue: 0.070)
        static let textSecondary = Color(red: 0.34, green: 0.36, blue: 0.41)
        static let textTertiary = Color(red: 0.58, green: 0.59, blue: 0.62)
        static let textInverse = Color.white

        static let primary = Color(red: 0.055, green: 0.39, blue: 0.90)
        static let onPrimary = Color.white
        static let primaryContainer = Color(red: 0.91, green: 0.95, blue: 1.00)
        static let onPrimaryContainer = Color(red: 0.04, green: 0.34, blue: 0.82)

        static let taskActive = Color(red: 0.03, green: 0.64, blue: 0.50)
        static let taskActiveContainer = Color(red: 0.91, green: 0.97, blue: 0.95)
        static let taskPaused = Color(red: 0.96, green: 0.39, blue: 0.08)
        static let taskPausedContainer = Color(red: 1.00, green: 0.94, blue: 0.86)
        static let taskComplete = Color(red: 0.20, green: 0.62, blue: 0.43)
        static let taskCompleteContainer = Color(red: 0.91, green: 0.97, blue: 0.93)
        static let taskIncomplete = Color(red: 0.96, green: 0.51, blue: 0.47)
        static let taskIncompleteContainer = Color(red: 1.00, green: 0.95, blue: 0.94)
        static let destructive = Color(red: 0.82, green: 0.18, blue: 0.20)

        // Goal colors identify branches only. They never communicate execution state.
        static let goalBlue = Color(red: 0.16, green: 0.44, blue: 0.82)
        static let goalTeal = Color(red: 0.12, green: 0.58, blue: 0.55)
        static let goalOrange = Color(red: 0.86, green: 0.48, blue: 0.20)
        static let goalViolet = Color(red: 0.48, green: 0.39, blue: 0.74)
    }

    enum TypeRole {
        static let displayLarge = Font.system(size: 38, weight: .black, design: .rounded)
        static let displayMedium = Font.system(size: 30, weight: .black, design: .rounded)
        static let headlineLarge = Font.system(size: 34, weight: .black, design: .rounded)
        static let headlineMedium = Font.system(size: 25, weight: .black, design: .rounded)
        static let headlineSmall = Font.system(size: 22, weight: .bold, design: .rounded)
        static let titleLarge = Font.system(size: 20, weight: .bold, design: .rounded)
        static let titleMedium = Font.system(size: 16, weight: .semibold)
        static let bodyMedium = Font.system(size: 15, weight: .regular)
        static let bodySmall = Font.system(size: 13, weight: .medium)
        static let labelLarge = Font.system(size: 15, weight: .semibold)
        static let labelMedium = Font.system(size: 13, weight: .semibold)
        static let labelSmall = Font.system(size: 11, weight: .semibold)
        static let timerLarge = Font.system(size: 38, weight: .black, design: .rounded).monospacedDigit()
        static let timerSmall = Font.system(size: 15, weight: .bold).monospacedDigit()
    }

    // Compatibility aliases keep the remaining V2 screens stable while they migrate.
    static let ink = ColorRole.textPrimary
    static let secondary = ColorRole.textSecondary
    static let tertiary = ColorRole.textTertiary
    static let page = ColorRole.canvas
    static let panel = ColorRole.surface
    static let line = ColorRole.outline
    static let blue = ColorRole.primary
    static let mint = ColorRole.taskActive
    static let orange = ColorRole.taskPaused
    static let violet = ColorRole.goalViolet

    static func goalColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "blue", "writing", "career":
            ColorRole.goalBlue
        case "mint", "teal", "health":
            ColorRole.goalTeal
        case "orange", "commitment", "admin":
            ColorRole.goalOrange
        case "violet", "growth", "learning":
            ColorRole.goalViolet
        default:
            ColorRole.textSecondary
        }
    }
}

extension View {
    func v2ScreenBackground() -> some View {
        background(V2Theme.page.ignoresSafeArea())
    }
}
