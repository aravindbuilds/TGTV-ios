import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var td: TDLibService
    @EnvironmentObject private var store: Store

    @State private var apiId = ""
    @State private var apiHash = ""
    @State private var phone = ""
    @State private var dialCode = Store.shared.dialCode
    @State private var code = ""
    @State private var password = ""
    @State private var botToken = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var botMode = false
    @State private var showAdvanced = false
    @State private var showCountryPicker = false

    /// Full international number: dial code + national digits.
    private var fullPhone: String {
        let digits = phone.filter { $0.isNumber }
        let typed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.hasPrefix("+") { return "+" + digits }
        return dialCode + digits
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)
                    VStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.red)
                        Text("TGTV")
                            .font(.system(size: 42, weight: .black))
                        Text("Your Telegram library, on every screen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    pane

                    if let error = td.lastError, !error.isEmpty {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if td.busy { ProgressView() }
                    Spacer()
                }
                .padding(24)
            }
            .navigationBarHidden(true)
        }
        .onAppear(perform: prefill)
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerView(selected: $dialCode)
        }
    }

    private func prefill() {
        if apiId.isEmpty, store.apiId > 0 { apiId = String(store.apiId) }
        if apiHash.isEmpty { apiHash = store.apiHash }
        if phone.isEmpty, !store.phone.isEmpty {
            let split = CountryCodes.split(store.phone)
            dialCode = split.dial
            phone = split.rest
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch td.phase {
        case .idle:
            ProgressView("Connecting…")

        case .waitParameters:
            // Baked credentials live inside the app, so never ask for them.
            if store.hasAPI && !showAdvanced {
                VStack(spacing: 10) {
                    ProgressView("Connecting to Telegram…")
                    Text("Using the API credentials built into this app.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("Use different API credentials") { showAdvanced = true }
                        .font(.caption)
                }
            } else {
                apiPane
            }

        case .waitPhoneNumber:
            VStack(spacing: 14) {
                if botMode {
                    SecureField("BotFather token", text: $botToken)
                        .textFieldStyle(.roundedBorder)
                    Button("Sign in as bot") { Task { await td.signIn(botToken: botToken) } }
                        .buttonStyle(.borderedProminent).tint(.red)
                    Button("Use phone number instead") { botMode = false }
                        .font(.caption)
                } else {
                    HStack(spacing: 8) {
                        Button { showCountryPicker = true } label: {
                            Text(dialCode)
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)

                        TextField("Number (no country code)", text: $phone)
                            .keyboardType(.phonePad)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text(fullPhone.isEmpty ? " " : "Signing in as \(fullPhone)")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("Send code") { Task { await td.signIn(phone: fullPhone) } }
                        .buttonStyle(.borderedProminent).tint(.red)
                        .disabled(phone.filter { $0.isNumber }.count < 6)
                    Button("Sign in with a bot token") { botMode = true }
                        .font(.caption)
                }
            }

        case .waitCode(let hint):
            VStack(spacing: 14) {
                Text("Verification code").font(.headline)
                if !hint.isEmpty { Text("Sent to \(hint)").font(.caption).foregroundStyle(.secondary) }
                TextField("Code", text: $code)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Button("Verify") { Task { await td.submit(code: code) } }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Resend code") { Task { await td.resendCode() } }
                    .font(.caption)
            }

        case .waitPassword(let hint):
            VStack(spacing: 14) {
                Text("Two-step verification").font(.headline)
                if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(.secondary) }
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                Button("Continue") { Task { await td.submit(password: password) } }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(password.isEmpty)
            }

        case .waitRegistration:
            VStack(spacing: 14) {
                Text("Create your Telegram account").font(.headline)
                TextField("First name", text: $firstName).textFieldStyle(.roundedBorder)
                TextField("Last name", text: $lastName).textFieldStyle(.roundedBorder)
                Button("Register") { Task { await td.register(firstName: firstName, lastName: lastName) } }
                    .buttonStyle(.borderedProminent).tint(.red)
            }

        case .ready:
            ProgressView("Opening library…")

        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.red)
                Button("Try again") { td.restart() }
            }
        }
    }

    private var apiPane: some View {
        VStack(spacing: 14) {
            Text("Telegram API credentials").font(.headline)
            TextField("API ID", text: $apiId)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            SecureField("API hash", text: $apiHash)
                .textFieldStyle(.roundedBorder)
            Button("Continue") {
                let id = Int64(apiId.trimmingCharacters(in: .whitespaces)) ?? store.apiId
                let hash = apiHash.isEmpty ? store.apiHash : apiHash
                Task {
                    do {
                        try await td.configure(apiId: id, apiHash: hash)
                    } catch {
                        td.lastError = tgErrorText(error)
                    }
                }
            }
            .buttonStyle(.borderedProminent).tint(.red)
            .disabled(apiId.isEmpty || apiHash.isEmpty)
            Text("Get these at my.telegram.org. They are stored only on this device.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct CountryPickerView: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    @State private var showCustom = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showCustom = true
                    } label: {
                        Label("Custom code…", systemImage: "plus.circle")
                    }
                }
                Section {
                    ForEach(CountryCodes.entries) { country in
                        Button {
                            selected = country.dial
                            Store.shared.dialCode = country.dial
                            dismiss()
                        } label: {
                            HStack {
                                Text(country.name)
                                Spacer()
                                Text(country.dial).foregroundStyle(.secondary)
                                if country.dial == selected {
                                    Image(systemName: "checkmark").foregroundStyle(.red)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Country code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Enter country code", isPresented: $showCustom) {
                TextField("+971", text: $custom)
                    .keyboardType(.phonePad)
                Button("Save") {
                    let raw = custom.trimmingCharacters(in: .whitespaces)
                        .filter { $0.isNumber || $0 == "+" }
                    guard !raw.isEmpty else { return }
                    let value = raw.hasPrefix("+") ? raw : "+" + raw
                    selected = value
                    Store.shared.dialCode = value
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
