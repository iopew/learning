import Foundation
import ActivityCore
#if canImport(FoundationModels) && arch(arm64)
import FoundationModels
#endif

/// Apple's on-device language model (macOS 26+, Apple Intelligence turned on): retells the rule-based day summary
/// as a few friendly sentences. Runs on this Mac only; nothing is sent anywhere. FoundationModels is weak-linked
/// (Package.swift), so older macOS versions start normally and simply don't offer it.
enum AIWriter {
    static var isAvailable: Bool {
        #if canImport(FoundationModels) && arch(arm64)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Why it isn't available, for the hint under the button.
    static var unavailableReason: String {
        #if canImport(FoundationModels) && arch(arm64)
        if #available(macOS 26.0, *) {
            return L.tr("Включи Apple Intelligence в Системных настройках, чтобы день пересказывала нейросеть прямо на Mac.",
                        "Turn on Apple Intelligence in System Settings to have the day retold by the on-device model.")
        }
        #endif
        return L.tr("Пересказ нейросетью доступен на macOS 26 и новее с Apple Intelligence.",
                    "Retelling with the on-device model needs macOS 26 or later with Apple Intelligence.")
    }

    /// Calls back on the main thread with the story, or nil (unavailable, refused, error).
    static func story(from facts: [String], completion: @escaping (String?) -> Void) {
        #if canImport(FoundationModels) && arch(arm64)
        if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let language = L.current == .en ? "English" : "Russian"
            let instructions = """
            You turn facts about one day of computer use into a short, friendly summary in \(language).
            Write 2–4 sentences addressed to the user ("you"). Use only the facts given; never invent apps,
            sites, times or numbers. Mention what took most of the morning, afternoon and evening, how focused the
            day was, and end with one gentle, practical suggestion. No lists, no headings.
            """
            Task {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let response = try await session.respond(to: facts.joined(separator: "\n"))
                    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run { completion(text.isEmpty ? nil : text) }
                } catch {
                    NSLog("ActivityTracker: on-device summary: \(error)")
                    await MainActor.run { completion(nil) }
                }
            }
            return
        }
        #endif
        completion(nil)
    }
}
