import SwiftUI

enum AppTheme {
    static let ink = Color(red: 0.09, green: 0.11, blue: 0.13)
    static let muted = Color(red: 0.43, green: 0.47, blue: 0.51)
    static let paper = Color(red: 0.98, green: 0.98, blue: 0.95)
    static let sage = Color(red: 0.85, green: 0.90, blue: 0.83)
    static let copper = Color(red: 0.89, green: 0.72, blue: 0.61)
    static let blue = Color(red: 0.87, green: 0.91, blue: 0.96)
    static let night = Color(red: 0.12, green: 0.14, blue: 0.17)

    static var dailyGradient: LinearGradient {
        LinearGradient(
            colors: [sage.opacity(0.72), paper],
            startPoint: .top,
            endPoint: .center
        )
    }

    static var focusGradient: LinearGradient {
        LinearGradient(
            colors: [sage, Color(red: 0.94, green: 0.91, blue: 0.84), copper],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var zenGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.09, blue: 0.11),
                Color(red: 0.18, green: 0.16, blue: 0.20),
                Color(red: 0.43, green: 0.29, blue: 0.24)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.dailyGradient.ignoresSafeArea())
            .foregroundStyle(AppTheme.ink)
    }
}

extension View {
    func dailyScreen() -> some View {
        modifier(ScreenBackground())
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .foregroundStyle(filled ? Color.white : AppTheme.ink)
            .background(filled ? AppTheme.ink : Color.white.opacity(0.62), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct TimelineMarker: View {
    var isSelected = false

    var body: some View {
        Circle()
            .fill(isSelected ? AppTheme.copper : AppTheme.sage)
            .frame(width: 9, height: 9)
            .overlay {
                Circle()
                    .stroke(isSelected ? AppTheme.night : AppTheme.paper, lineWidth: 4)
            }
    }
}
