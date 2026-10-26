import AppKit
import CoreImage
import SwiftUI
import ActivityCore

/// Settings → iPhone: pair the iPhone app with a QR code, send a snapshot through AirDrop, unpair.
struct PhoneSection: View {
    @ObservedObject var server: PhoneServer
    @ObservedObject var installer: PhoneInstaller
    @State private var showingCode = false
    @State private var teamID = UserDefaults.standard.string(forKey: PhoneInstaller.manualTeamKey) ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("iPhone").font(.headline)
            installSection
            Divider().padding(.vertical, 2)
            if let pairing = server.pairing {
                HStack {
                    Button(showingCode ? L.tr("Скрыть QR-код", "Hide the QR code") : L.tr("Показать QR-код", "Show the QR code")) {
                        showingCode.toggle()
                    }
                    Button(L.tr("Отправить снимок через AirDrop", "Send a snapshot via AirDrop")) { server.sendViaAirDrop() }
                    Button(L.tr("Отвязать", "Unpair")) {
                        showingCode = false
                        server.unpair()
                    }
                }
                if showingCode { code(for: pairing) }
                Text(server.lastServed.map {
                    L.tr("iPhone забирал статистику \(Format.relative($0)).", "The iPhone last fetched statistics \(Format.relative($0)).")
                } ?? L.tr("iPhone ещё не забирал статистику с момента запуска.", "The iPhone hasn't fetched statistics since launch."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(L.tr("Связать с iPhone", "Pair with an iPhone")) {
                    server.pair()
                    showingCode = true
                }
            }
            if let problem = server.problem {
                Text(problem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text(L.tr("Приложение ActivityTracker на iPhone забирает готовые отчёты прямо с этого Mac, когда они в одной сети: дома, через режим модема iPhone или на работе. Без облака: данные зашифрованы ключом из QR-кода, и без него никто в сети их не получит. Заголовки окон и адреса страниц на телефон не передаются. Если в сети устройства не видят друг друга — отправь снимок через AirDrop.",
                      "The ActivityTracker iPhone app fetches ready reports straight from this Mac when both are on one network: at home, through the iPhone's hotspot or at work. No cloud: the data is encrypted with the key in the QR code, and nobody on the network gets it without that key. Window titles and page addresses are not sent. If devices can't see each other on a network, send a snapshot via AirDrop."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Step 1: put the app on the iPhone (and every 7 days again, to renew the free signature).
    private var installSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(installer.lastInstall == nil ? L.tr("Установить на iPhone", "Install on iPhone")
                                                    : L.tr("Обновить приложение на iPhone", "Update the app on iPhone")) {
                    installer.install()
                }
                .disabled(installer.isWorking)
                if installer.isWorking { ProgressView().controlSize(.small) }
                Button(L.tr("Журнал", "Log")) { NSWorkspace.shared.open(PhoneInstaller.logURL) }
                    .buttonStyle(.link)
                    .opacity(FileManager.default.fileExists(atPath: PhoneInstaller.logURL.path) ? 1 : 0)
            }
            switch installer.phase {
            case .idle:
                EmptyView()
            case .working(let text):
                Text(text).font(.caption).foregroundStyle(.secondary)
            case .done(let text):
                Text(text).font(.caption).foregroundStyle(.green).fixedSize(horizontal: false, vertical: true)
            case .failed(let text):
                Text(text).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            switch installer.fix {
            case .installXcode:
                Button(L.tr("Открыть Xcode в App Store", "Open Xcode in the App Store")) {
                    NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/id497799835")!)
                }
            case .signIn:
                HStack {
                    Button(L.tr("Открыть Xcode", "Open Xcode")) {
                        if let xcode = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") {
                            NSWorkspace.shared.openApplication(at: xcode, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }
                    TextField("Team ID", text: $teamID)
                        .frame(width: 140)
                        .onSubmit { saveTeamID() }
                    Button(L.tr("Сохранить и установить", "Save and install")) {
                        saveTeamID()
                        installer.install()
                    }
                    .disabled(teamID.trimmingCharacters(in: .whitespaces).count != 10)
                }
            case .none:
                EmptyView()
            }
            if let last = installer.lastInstall, !installer.isWorking {
                let expires = last.addingTimeInterval(7 * 86_400)
                Text(expires > Date()
                     ? L.tr("Установлено \(Format.relative(last)). С бесплатным Apple ID подпись действует до \(expires.formatted(date: .abbreviated, time: .omitted)) — потом нажми кнопку снова.",
                            "Installed \(Format.relative(last)). With a free Apple ID the signature lasts until \(expires.formatted(date: .abbreviated, time: .omitted)) — then press the button again.")
                     : L.tr("Подпись истекла — подключи iPhone и нажми «Обновить приложение на iPhone».",
                            "The signature has expired — connect the iPhone and press “Update the app on iPhone”."))
                    .font(.caption)
                    .foregroundStyle(expires > Date() ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L.tr("Нужны: Xcode (App Store), вход в Xcode своим Apple ID (Xcode → Settings → Accounts, один раз), iPhone на кабеле с включённым режимом разработчика. Код скачивается с GitHub, собирается и подписывается на этом Mac; Xcode открывать не нужно. macOS может спросить пароль от связки ключей для codesign — нажми «Всегда разрешать».",
                      "Needed: Xcode (App Store), your Apple ID signed in to Xcode (Xcode → Settings → Accounts, once), the iPhone on a cable with Developer Mode on. The source is downloaded from GitHub, built and signed on this Mac; Xcode doesn't need to be opened. macOS may ask for the keychain password for codesign — choose “Always Allow”."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func code(for pairing: PhoneLink.Pairing) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = Self.qrImage(PhoneLink.encode(pairing)) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
            }
            Text(L.tr("Открой ActivityTracker на iPhone → «Связать с Mac» и наведи камеру на код. Код — это ключ: не показывай его другим. «Отвязать» делает старый код бесполезным.",
                      "Open ActivityTracker on the iPhone → “Pair with Mac” and point the camera at the code. The code is the key: don't show it to others. “Unpair” makes an old code useless."))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveTeamID() {
        let value = teamID.trimmingCharacters(in: .whitespaces).uppercased()
        UserDefaults.standard.set(value.isEmpty ? nil : value, forKey: PhoneInstaller.manualTeamKey)
    }

    static func qrImage(_ text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
