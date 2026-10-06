import SwiftUI

struct AdminLicensesView: View {
    @Environment(\.appLanguage) private var language
    @State private var token = ""
    @State private var policyID = ""
    @State private var licenseName = ""
    @State private var licenses: [AdminLicense] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SecureField(language.text("admin.token"), text: $token)
                        .textContentType(.password)
                    Text(language.text("admin.token_footer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(language.text("admin.connect")) { refresh() }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                } header: {
                    Label(language.text("admin.access"), systemImage: "lock.shield")
                }

                if !licenses.isEmpty {
                    Section(language.text("admin.licenses")) {
                        ForEach(licenses) { license in
                            licenseRow(license)
                        }
                    }
                }
            }
            .navigationTitle(language.text("admin.title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { token = ""; licenses = [] } label: {
                        Image(systemName: "lock.open")
                    }
                    .accessibilityLabel(language.text("admin.disconnect"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(token.isEmpty)
                    .accessibilityLabel(language.text("admin.create"))
                }
            }
            .overlay { if isLoading { ProgressView() } }
            .alert(language.text("common.error"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(language.text("common.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showCreate) {
                NavigationStack {
                    Form {
                        TextField(language.text("admin.name"), text: $licenseName)
                        TextField(language.text("admin.policy_id"), text: $policyID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .navigationTitle(language.text("admin.create"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(language.text("common.cancel")) { showCreate = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(language.text("common.save")) { createLicense() }
                                .disabled(policyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }

    private func licenseRow(_ license: AdminLicense) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(license.name?.isEmpty == false ? license.name! : license.key)
                    .font(.headline)
                Spacer()
                Text(license.status ?? "—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(license.status == "SUSPENDED" ? .orange : .secondary)
            }
            if !license.key.isEmpty && license.name?.isEmpty == false {
                Text(license.key).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if let expiry = license.expiry {
                Text(expiry.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(language.text(license.status == "SUSPENDED" ? "admin.reinstate" : "admin.suspend")) {
                    changeStatus(license, suspended: license.status != "SUSPENDED")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button(language.text("admin.revoke"), role: .destructive) {
                    revoke(license)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func refresh() {
        guard !token.isEmpty else { return }
        isLoading = true
        Task {
            do { licenses = try await AdminLicenseClient.list(token: token) }
            catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }

    private func createLicense() {
        isLoading = true
        Task {
            do {
                let created = try await AdminLicenseClient.create(
                    name: licenseName,
                    policyID: policyID,
                    token: token
                )
                licenses.insert(created, at: 0)
                licenseName = ""
                policyID = ""
                showCreate = false
            } catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }

    private func changeStatus(_ license: AdminLicense, suspended: Bool) {
        isLoading = true
        Task {
            do {
                if suspended {
                    try await AdminLicenseClient.suspend(id: license.id, token: token)
                } else {
                    try await AdminLicenseClient.reinstate(id: license.id, token: token)
                }
                refresh()
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func revoke(_ license: AdminLicense) {
        isLoading = true
        Task {
            do {
                try await AdminLicenseClient.revoke(id: license.id, token: token)
                licenses.removeAll { $0.id == license.id }
            } catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }
}
