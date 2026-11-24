import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var td: TDLibService
    @EnvironmentObject private var store: Store

    @State private var apiId = ""
    @State private var apiHash = ""
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""
    @State private var botToken = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var botMode = false
    @State private var showAdvanced = false

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
    }

    @ViewBuilder
    private var pane: some View {
        switch td.phase {
        case .idle:
            ProgressView("Connecting…")

        case .waitParameters:
            VStack(spacing: 14) {
                Text("Telegram API credentials").font(.headline)
                TextField("API ID", text: $apiId)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                SecureField("API hash", text: $apiHash)
                    .textFieldStyle(.roundedBorder)
                Button("Continue") {
                    let id = Int64(apiId) ?? store.apiId
                    let hash = apiHash.isEmpty ? store.apiHash : apiHash
                    Task { try? await td.configure(apiId: id, apiHash: hash) }
                }
                .buttonStyle(.borderedProminent).tint(.red)
                Text("Get these at my.telegram.org. They are stored only on this device.")
                    .font(.caption2).foregroundStyle(.secondary)
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
                    TextField("Phone number (+…)", text: $phone)
                        .keyboardType(.phonePad)
                        .textFieldStyle(.roundedBorder)
                    Button("Send code") { Task { await td.signIn(phone: phone) } }
                        .buttonStyle(.borderedProminent).tint(.red)
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
            }

        case .waitPassword(let hint):
            VStack(spacing: 14) {
                Text("Two-step verification").font(.headline)
                if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(.secondary) }
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                Button("Continue") { Task { await td.submit(password: password) } }
                    .buttonStyle(.borderedProminent).tint(.red)
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
}
