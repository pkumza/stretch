import Foundation

struct BreakMessages {
    let short: [String]
    let long: [String]
}

final class MessageStore {
    static let shared = MessageStore()

    private let fallback = BreakMessages(
        short: [
            "Follow the 20-20-20 rule: look at something 20 feet away for 20 seconds.",
            "Blink slowly a few times and let your eyes refocus.",
            "Look away from the screen and relax your face.",
            "Unclench your jaw, drop your shoulders, and breathe.",
            "Roll your shoulders back and loosen your neck.",
            "Rest your hands and stretch your wrists gently.",
            "Sit tall, soften your gaze, and reset your posture.",
            "Close your eyes briefly and take two slow breaths.",
        ],
        long: [
            "Stand up and walk around for a few minutes.",
            "Get a glass of water and stretch your legs.",
            "Step away from the screen and look out a window.",
            "Do a few gentle stretches for your back, neck, and shoulders.",
            "Take a short walk and let your posture reset.",
            "Move your hips, knees, and ankles before sitting again.",
            "Shake out your hands and loosen your forearms.",
            "Leave the desk for a moment and come back with fresh eyes.",
        ])

    private init() {}

    func randomMessage(for type: BreakType) -> String {
        let messages = loadMessages()
        let pool = type.isLong ? messages.long : messages.short
        return pool.randomElement() ?? ""
    }

    private func loadMessages() -> BreakMessages {
        for url in candidateFiles() {
            if let messages = parseJSONL(url: url), !messages.short.isEmpty || !messages.long.isEmpty {
                return BreakMessages(
                    short: messages.short.isEmpty ? fallback.short : messages.short,
                    long: messages.long.isEmpty ? fallback.long : messages.long)
            }
        }
        return fallback
    }

    private func candidateFiles() -> [URL] {
        var urls: [URL] = []
        let fm = FileManager.default

        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(support.appendingPathComponent("Stretch/message.jsonl"))
        }

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        urls.append(cwd.appendingPathComponent("message.jsonl"))

        urls.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/message.jsonl"))

        if let bundleRoot = Bundle.main.bundleURL.deletingLastPathComponentIfAppBundle {
            urls.append(bundleRoot.appendingPathComponent("message.jsonl"))
        }

        return urls
    }

    private func parseJSONL(url: URL) -> BreakMessages? {
        guard let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8) else {
            return nil
        }

        var short: [String] = []
        var long: [String] = []

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }

            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = object["message"] as? String else {
                continue
            }

            let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let source = (object["source"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let display = source.map { "\(cleaned)\n-- \($0)" } ?? cleaned

            switch (object["type"] as? String)?.lowercased() {
            case "short":
                short.append(display)
            case "long":
                long.append(display)
            default:
                short.append(display)
                long.append(display)
            }
        }

        return BreakMessages(short: short, long: long)
    }
}

private extension URL {
    var deletingLastPathComponentIfAppBundle: URL? {
        guard pathExtension == "app" else { return nil }
        return deletingLastPathComponent()
    }
}
