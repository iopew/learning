import AVFoundation
import SwiftUI
import VisionKit
import ActivityCore

struct SettingsTab: View {
    @EnvironmentObject private var model: PhoneModel
    @State private var scanning = false
    @State private var scanProblem: String?
    @State private var confirmUnpair = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    if let pairing = model.pairing {
                        LabeledContent(L.tr("Связан с", "Paired with"), value: pairing.macName)
                        if let sync = model.lastSync {
                            LabeledContent(L.tr("Последнее обновление", "Last update"), value: Format.relative(sync))
                        }
                        if let host = model.lastHost {
                            LabeledContent(L.tr("Адрес", "Address"), value: host)
                        }
                        Button(L.tr("Связать заново", "Pair again")) { scanning = true }
                        Button(L.tr("Отвязать", "Unpair"), role: .destructive) { confirmUnpair = true }
                    } else {
                        Button(L.tr("Связать с Mac", "Pair with Mac")) { scanning = true }
                    }
                    if let scanProblem { Text(scanProblem).foregroundStyle(.red) }
                }
                Section {
                    TextField(L.tr("например 100.101.102.103", "e.g. 100.101.102.103"), text: $model.manualHost)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(L.tr("Адрес Mac вручную", "Mac address (manual)"))
                } footer: {
                    Text(L.tr("Чтобы видеть статистику вне общей сети, поставь Tailscale на Mac и iPhone (один аккаунт) и впиши сюда адрес Mac в Tailscale (100.x.y.z) или его имя. Если Tailscale уже был включён при связке, адрес подставится сам.",
                              "To see statistics away from a shared network, install Tailscale on the Mac and the iPhone (one account) and enter the Mac's Tailscale address (100.x.y.z) or name here. If Tailscale was on when you paired, the address is already known."))
                }
                Section {
                    Text(L.tr("Статистика приходит прямо с Mac, без облака, зашифрованной ключом из QR-кода. На iPhone хранится только последний снимок отчётов (без заголовков окон и адресов страниц) и замеры батареи и трафика этого iPhone.",
                              "Statistics come straight from the Mac, without a cloud, encrypted with the key from the QR code. The iPhone keeps only the latest report snapshot (no window titles or page addresses) and this iPhone's battery and traffic readings."))
                        .font(.footnote)
                    Text(L.tr("Приложение подписано бесплатным Apple ID: раз в 7 дней его нужно заново запустить из Xcode на Mac (данные сохраняются).",
                              "The app is signed with a free Apple ID: every 7 days run it again from Xcode on the Mac (data is kept)."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L.tr("Настройки", "Settings"))
            .sheet(isPresented: $scanning) {
                QRScannerSheet { code in
                    scanning = false
                    scanProblem = model.pair(code: code) ? nil : L.tr("Это не код ActivityTracker", "This isn't an ActivityTracker code")
                }
            }
            .confirmationDialog(L.tr("Отвязать Mac? Снимок статистики на iPhone удалится.", "Unpair the Mac? The statistics snapshot on the iPhone is deleted."),
                                isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button(L.tr("Отвязать", "Unpair"), role: .destructive) { model.unpair() }
            }
        }
    }
}

/// The camera looking for the QR code shown in the Mac's settings.
struct QRScannerSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    /// nil while the camera permission is being asked.
    @State private var available: Bool?

    var body: some View {
        NavigationStack {
            Group {
                if available == nil {
                    ProgressView()
                } else if available == true {
                    QRScanner(onCode: onCode).ignoresSafeArea()
                } else {
                    ContentUnavailableView(L.tr("Камера недоступна", "Camera unavailable"), systemImage: "camera",
                                           description: Text(L.tr("Разреши доступ к камере в Настройках iPhone → ActivityTracker.",
                                                                  "Allow camera access in iPhone Settings → ActivityTracker.")))
                }
            }
            .task {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                available = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
            }
            .navigationTitle(L.tr("QR-код с Mac", "QR code on the Mac"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.tr("Отмена", "Cancel")) { dismiss() } }
            }
        }
    }
}

struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var reported = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items {
                if case .barcode(let barcode) = item, let text = barcode.payloadStringValue, !reported {
                    reported = true
                    scanner.stopScanning()
                    onCode(text)
                }
            }
        }
    }
}
