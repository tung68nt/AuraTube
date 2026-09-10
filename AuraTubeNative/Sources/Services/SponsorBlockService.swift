import Foundation

public final class SponsorBlockService: @unchecked Sendable {
    public static let shared = SponsorBlockService()
    
    private init() {}
    
    public func fetchSegments(videoId: String) async -> [SponsorSegment] {
        guard let url = URL(string: "https://sponsor.ajay.app/api/skipSegments?videoID=\(videoId)&categories=[\"sponsor\",\"intro\",\"outro\",\"interaction\",\"selfpromo\"]") else {
            return []
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 4.0
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            
            struct RawSegment: Codable {
                let category: String
                let segment: [Double]
            }
            
            let decoded = try JSONDecoder().decode([RawSegment].self, from: data)
            return decoded.map { SponsorSegment(category: $0.category, start: $0.segment.first ?? 0, end: $0.segment.count > 1 ? $0.segment[1] : 0) }
        } catch {
            return []
        }
    }
}
