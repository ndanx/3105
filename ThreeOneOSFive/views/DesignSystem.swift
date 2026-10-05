import SwiftUI

enum AppThemeColor: String, CaseIterable, Identifiable {
    static let storageKey = "appThemeColor"

    case orange
    case red
    case blue
    case green

    var id: String { rawValue }

    var titleKey: String { "settings.theme_\(rawValue)" }

    static var current: AppThemeColor {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap(AppThemeColor.init(rawValue:)) ?? .orange
    }

    var color: Color {
        let pair = components
        return Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? pair.dark : pair.light
            }
        )
    }

    private var components: (dark: UIColor, light: UIColor) {
        switch self {
        case .orange:
            return (
                UIColor(red: 1.00, green: 0.64, blue: 0.42, alpha: 1.00),
                UIColor(red: 0.85, green: 0.42, blue: 0.20, alpha: 1.00)
            )
        case .red:
            return (
                UIColor(red: 1.00, green: 0.40, blue: 0.40, alpha: 1.00),
                UIColor(red: 0.80, green: 0.15, blue: 0.15, alpha: 1.00)
            )
        case .blue:
            return (
                UIColor(red: 0.40, green: 0.65, blue: 1.00, alpha: 1.00),
                UIColor(red: 0.10, green: 0.40, blue: 0.85, alpha: 1.00)
            )
        case .green:
            return (
                UIColor(red: 0.35, green: 0.85, blue: 0.50, alpha: 1.00),
                UIColor(red: 0.10, green: 0.60, blue: 0.30, alpha: 1.00)
            )
        }
    }
}

enum AppTheme {
    static var accent: Color { AppThemeColor.current.color }
    static let pageBackground = Color(uiColor: .systemBackground)
    static let consoleBackground = Color(uiColor: .secondarySystemBackground)
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.12))
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}

struct AppSearchField: View {
    @Binding var text: String
    let prompt: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(
            Color(uiColor: .secondarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let icon = UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}
