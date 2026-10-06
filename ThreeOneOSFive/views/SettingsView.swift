import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var license: LicenseManager
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @AppStorage(AppThemeColor.storageKey) private var themeColorCode = AppThemeColor.orange.rawValue
    @State private var selectedTheme = AppThemeColor.current
    @State private var showChangeKeyConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AppLogo()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("3105").font(.headline)
                            Text(language.text("common.version", appVersion))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    LabeledContent(language.text("license.expires"), value: expiryText)
                    LabeledContent(language.text("license.remaining"), value: remainingText)
                    Button(role: .destructive) {
                        showChangeKeyConfirm = true
                    } label: {
                        Text(language.text("license.change_key"))
                    }
                } header: {
                    Text(language.text("license.section"))
                }

                Section(language.text("settings.language")) {
                    Picker(language.text("settings.language"), selection: $languageCode) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section(language.text("common.device")) {
                    LabeledContent(language.text("dashboard.hardware_model"), value: AppInfo.displayMachineName)
                    LabeledContent(language.text("settings.ios_version"), value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                    HStack {
                        Text(language.text("settings.theme"))
                        Spacer()
                        HStack(spacing: 14) {
                            ForEach(AppThemeColor.allCases) { option in
                                Button {
                                    selectedTheme = option
                                } label: {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 26, height: 26)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    Color.primary,
                                                    lineWidth: selectedTheme == option ? 2 : 0
                                                )
                                                .padding(-4)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(language.text(option.titleKey))
                                .accessibilityAddTraits(selectedTheme == option ? .isSelected : [])
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Text(language.text("settings.current_version"))
                        Spacer()
                        Text(language.text(appState.isSupported ? "settings.supported" : "settings.unsupported"))
                        .foregroundStyle(appState.isSupported ? Color.green : Color.red)
                    }
                    LabeledContent("iOS 17", value: ExploitSupportPolicy.verifiedIOS17Range)
                    LabeledContent("iOS 18", value: ExploitSupportPolicy.verifiedIOS18Range)
                    LabeledContent("iOS 26", value: ExploitSupportPolicy.verifiedIOS26Range)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("iOS 27.0")
                            .font(.body)
                        ForEach(ExploitSupportPolicy.verifiedIOS27Builds, id: \.build) { version in
                            Text(versionLabel(version))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text(language.text("settings.verified_versions"))
                } footer: {
                    Text(language.text("settings.supported_versions_footer"))
                }

                Section(language.text("settings.social_media")) {
                    creditsRow(
                        name: "GitHub",
                        role: language.text("social.github_role"),
                        url: "https://github.com/YangJiiii/3105"

                    )
                }

                Section(language.text("settings.credits")) {
                    creditsRow(
                        name: "Dan Vip",
                        role: language.text("credit.danvip"),
                        url: "https://www.instagram.com/dant211_vc/"
                    )
                }
            }
            .tint(selectedTheme.color)
            .alert(language.text("license.change_title"), isPresented: $showChangeKeyConfirm) {
                Button(language.text("license.change_key"), role: .destructive) {
                    license.signOut()
                }
                Button(language.text("common.cancel"), role: .cancel) {}
            } message: {
                Text(language.text("license.change_message"))
            }
            .onDisappear {
                if themeColorCode != selectedTheme.rawValue {
                    themeColorCode = selectedTheme.rawValue
                }
            }
            .navigationTitle(language.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var expiryText: String {
        guard let expiry = license.expiry else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: expiry)
    }

    private var remainingText: String {
        guard let expiry = license.expiry else { return "—" }
        let seconds = expiry.timeIntervalSinceNow
        let days = Int(seconds / 86_400)
        if seconds <= 0 || days < 1 { return language.text("license.remaining_less") }
        if days == 1 { return language.text("license.remaining_one_day") }
        return language.text("license.remaining_days", Int64(days))
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    private func versionLabel(
        _ version: (beta: Int, publicBeta: Int?, build: String)
    ) -> String {
        if let publicBeta = version.publicBeta {
            return language.text(
                "settings.developer_public_beta_build",
                Int64(version.beta),
                Int64(publicBeta),
                version.build
            )
        }
        return language.text(
            "settings.developer_beta_build",
            Int64(version.beta),
            version.build
        )
    }

    @ViewBuilder
    private func creditsRow(name: String, role: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selectedTheme.color)
                        .frame(width: 28, height: 28)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(language.text("accessibility.open_profile", name))
        }
    }
}
