import SwiftUI

struct LicenseView: View {
    @ObservedObject var license: LicenseManager
    @Environment(\.appLanguage) private var language
    @State private var keyText = ""
    @FocusState private var keyFocused: Bool

    private var isChecking: Bool { license.status == .checking }

    private var failure: LicenseFailure? {
        if case .blocked(let failure) = license.status { return failure }
        return nil
    }

    private var canSubmit: Bool {
        !keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !license.isWorking
    }

    var body: some View {
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 40)

                    AppLogo(size: 76)

                    VStack(spacing: 6) {
                        Text(language.text("license.title"))
                            .font(.title2.weight(.bold))
                        Text(language.text("license.subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if isChecking {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(language.text("license.checking"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    } else {
                        form
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, AppTheme.pageInset + 8)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .tint(AppTheme.accent)
    }

    private var form: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField(language.text("license.placeholder"), text: $keyText)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($keyFocused)
                    .onSubmit(submit)
                    .disabled(license.isWorking)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(
                Color(uiColor: .secondarySystemFill),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            if let failure {
                errorBanner(failure)
            }

            Button(action: submit) {
                Text(language.text("license.activate"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit)

            if license.hasStoredKey {
                Button {
                    keyFocused = false
                    license.revalidate()
                } label: {
                    Text(language.text("license.retry"))
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(license.isWorking)
            }
        }
    }

    private func errorBanner(_ failure: LicenseFailure) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: failure == .offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.red)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(message(for: failure))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            Color.red.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func message(for failure: LicenseFailure) -> String {
        if let detail = failure.detail {
            return language.text(failure.messageKey, detail)
        }
        return language.text(failure.messageKey)
    }

    private func submit() {
        guard canSubmit else { return }
        keyFocused = false
        license.activate(keyText)
    }
}
