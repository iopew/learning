import AppKit
import CoreImage
import SwiftUI
import ActivityCore

/// Settings → iPhone: pair the iPhone app with a QR code, send a snapshot through AirDrop, unpair.
struct PhoneSection: View {
    @ObservedObject var server: PhoneServer
    @State private var showingCode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("iPhone").font(.headline)
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
