import Foundation
import AppKit

public struct YouTubeURLParseResult: Identifiable, Equatable {
    public var id: String { videoId }
    public let videoId: String
    public let startTime: Double?
    public let isShort: Bool
    public let originalInput: String
    
    public var webUrl: String {
        if let start = startTime, start > 0 {
            return "https://www.youtube.com/watch?v=\(videoId)&t=\(Int(start))s"
        }
        return "https://www.youtube.com/watch?v=\(videoId)"
    }
}

public enum YouTubeURLParser {
    
    /// Parses any YouTube URL, short link, or 11-character video ID.
    public static func parse(_ rawInput: String) -> YouTubeURLParseResult? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        
        // 1. Check if raw video ID (exact 11 characters: [a-zA-Z0-9_-])
        let rawIdRegex = "^[a-zA-Z0-9_-]{11}$"
        if input.range(of: rawIdRegex, options: .regularExpression) != nil {
            return YouTubeURLParseResult(
                videoId: input,
                startTime: nil,
                isShort: false,
                originalInput: input
            )
        }
        
        // 2. Structured URL check
        var candidateUrlString = input
        if !candidateUrlString.lowercased().hasPrefix("http://") && !candidateUrlString.lowercased().hasPrefix("https://") {
            candidateUrlString = "https://" + candidateUrlString
        }
        
        var extractedId: String? = nil
        var isShort = false
        var startTime: Double? = nil
        
        if let url = URL(string: candidateUrlString),
           let host = url.host?.lowercased(),
           host.contains("youtube.com") || host.contains("youtu.be") {
            
            let path = url.path
            
            // A. youtu.be/<id>
            if host.contains("youtu.be") {
                let comps = path.split(separator: "/").map(String.init)
                if let first = comps.first, first.count >= 11 {
                    extractedId = String(first.prefix(11))
                }
            }
            // B. youtube.com/shorts/<id>
            else if path.contains("/shorts/") {
                isShort = true
                let comps = path.split(separator: "/").map(String.init)
                if let idx = comps.firstIndex(of: "shorts"), idx + 1 < comps.count {
                    let c = comps[idx + 1]
                    if c.count >= 11 { extractedId = String(c.prefix(11)) }
                }
            }
            // C. youtube.com/live/<id>
            else if path.contains("/live/") {
                let comps = path.split(separator: "/").map(String.init)
                if let idx = comps.firstIndex(of: "live"), idx + 1 < comps.count {
                    let c = comps[idx + 1]
                    if c.count >= 11 { extractedId = String(c.prefix(11)) }
                }
            }
            // D. youtube.com/embed/<id>
            else if path.contains("/embed/") {
                let comps = path.split(separator: "/").map(String.init)
                if let idx = comps.firstIndex(of: "embed"), idx + 1 < comps.count {
                    let c = comps[idx + 1]
                    if c.count >= 11 { extractedId = String(c.prefix(11)) }
                }
            }
            // E. youtube.com/watch?v=<id>
            else if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let vParam = components.queryItems?.first(where: { $0.name == "v" })?.value, vParam.count >= 11 {
                    extractedId = String(vParam.prefix(11))
                }
            }
            
            // Extract timestamp if present (?t=123s, ?start=123, &t=1m30s)
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let tParam = components.queryItems?.first(where: { $0.name == "t" || $0.name == "start" })?.value {
                    startTime = parseTimeString(tParam)
                }
            }
        }
        
        // 3. Fallback: NSRegularExpression extraction over string
        if extractedId == nil {
            let pattern = #"(?:youtu\.be\/|youtube\.com\/(?:watch\?.*v=|shorts\/|live\/|embed\/))([a-zA-Z0-9_-]{11})"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)),
               let range = Range(match.range(at: 1), in: input) {
                extractedId = String(input[range])
                if input.contains("/shorts/") {
                    isShort = true
                }
            }
        }
        
        // Extract timestamp from string if not yet found
        if startTime == nil && (input.contains("t=") || input.contains("start=")) {
            let tPattern = #"[?&](?:t|start)=([0-9hms]+)"#
            if let regex = try? NSRegularExpression(pattern: tPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)),
               let range = Range(match.range(at: 1), in: input) {
                startTime = parseTimeString(String(input[range]))
            }
        }
        
        guard let finalId = extractedId, finalId.count == 11 else { return nil }
        
        return YouTubeURLParseResult(
            videoId: finalId,
            startTime: startTime,
            isShort: isShort,
            originalInput: input
        )
    }
    
    /// Inspect the macOS clipboard and parse if a valid YouTube link is copied
    public static func checkClipboard() -> YouTubeURLParseResult? {
        guard let pasteboardString = NSPasteboard.general.string(forType: .string) else {
            return nil
        }
        return parse(pasteboardString)
    }
    
    /// Parse time string such as "120", "120s", "1m30s", "1h2m3s" into seconds
    public static func parseTimeString(_ raw: String) -> Double? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let direct = Double(clean.replacingOccurrences(of: "s", with: "")) {
            return direct
        }
        
        var totalSeconds: Double = 0
        var currentNumber = ""
        
        for char in clean {
            if char.isNumber {
                currentNumber.append(char)
            } else if char == "h" {
                if let hours = Double(currentNumber) {
                    totalSeconds += hours * 3600
                }
                currentNumber = ""
            } else if char == "m" {
                if let minutes = Double(currentNumber) {
                    totalSeconds += minutes * 60
                }
                currentNumber = ""
            } else if char == "s" {
                if let seconds = Double(currentNumber) {
                    totalSeconds += seconds
                }
                currentNumber = ""
            }
        }
        
        if !currentNumber.isEmpty, let leftover = Double(currentNumber) {
            totalSeconds += leftover
        }
        
        return totalSeconds > 0 ? totalSeconds : nil
    }
    
    /// Generate standard or timestamped share link
    public static func makeShareURL(videoId: String, timestamp: Double? = nil) -> String {
        if let ts = timestamp, ts > 1.0 {
            return "https://www.youtube.com/watch?v=\(videoId)&t=\(Int(ts))s"
        }
        return "https://www.youtube.com/watch?v=\(videoId)"
    }
}
