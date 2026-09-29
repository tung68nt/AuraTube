import SwiftUI
import AppKit

public struct OpenYouTubeURLSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var urlText: String = ""
    @State private var parsedResult: YouTubeURLParseResult? = nil
    @State private var hasCheckedClipboard: Bool = false
    
    let onPlay: (YouTubeURLParseResult) -> Void
    
    public init(initialURL: String = "", onPlay: @escaping (YouTubeURLParseResult) -> Void) {
        self._urlText = State(initialValue: initialURL)
        self.onPlay = onPlay
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.cyan)
                    
                    Text("Mở Video YouTube từ Liên kết")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider()
                .background(ThemeColor.divider(for: colorScheme))
            
            // Content
            VStack(alignment: .leading, spacing: 18) {
                Text("Dán liên kết video bất kỳ từ YouTube (watch, shorts, live, embed, youtu.be) hoặc nhập ID 11 ký tự để phát ngay lập tức:")
                    .font(.system(size: 12.5))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .lineSpacing(3)
                
                // Input Container
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        
                        TextField("https://www.youtube.com/watch?v=... hoặc youtu.be/...", text: $urlText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .onChange(of: urlText) { newText in
                                validateURL(newText)
                            }
                            .onSubmit {
                                if let result = parsedResult {
                                    dismiss()
                                    onPlay(result)
                                }
                            }
                        
                        if !urlText.isEmpty {
                            Button(action: {
                                urlText = ""
                                parsedResult = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Paste from Clipboard Button
                        Button(action: pasteFromClipboard) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Dán")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        parsedResult != nil ? Color.green.opacity(0.6) : (colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1)),
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                
                // Detection Preview Card
                if let result = parsedResult {
                    HStack(spacing: 14) {
                        // Thumbnail Preview
                        CachedAsyncThumbnail(
                            url: "https://i.ytimg.com/vi/\(result.videoId)/hqdefault.jpg",
                            maxPixelSize: 240,
                            placeholderColor: colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.88)
                        )
                        .frame(width: 96, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.75)
                        )
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                                Text("Liên kết hợp lệ")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.green)
                                
                                if result.isShort {
                                    Text("Shorts")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.red))
                                }
                            }
                            
                            Text("Video ID: \(result.videoId)")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            
                            if let startTime = result.startTime, startTime > 0 {
                                let m = Int(startTime) / 60
                                let s = Int(startTime) % 60
                                Text(String(format: "Bắt đầu tại mốc thời gian: %02d:%02d", m, s))
                                    .font(.system(size: 11))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.green.opacity(colorScheme == .dark ? 0.12 : 0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.green.opacity(0.3), lineWidth: 0.75)
                            )
                    )
                } else if !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("Chưa nhận dạng được liên kết YouTube hợp lệ. Vui lòng kiểm tra lại URL.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 4)
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Spacer()
                    
                    Button("Huỷ") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    
                    Button(action: {
                        if let result = parsedResult {
                            dismiss()
                            onPlay(result)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Phát ngay")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(parsedResult != nil ? Color(red: 1.0, green: 0.1, blue: 0.1) : Color.gray.opacity(0.4))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(parsedResult == nil)
                }
                .padding(.top, 6)
            }
            .padding(22)
        }
        .frame(width: 480)
        .background(
            ZStack {
                VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
                if colorScheme == .dark {
                    Color(red: 22/255, green: 22/255, blue: 26/255).opacity(0.96)
                } else {
                    Color.white.opacity(0.96)
                }
            }
        )
        .onAppear {
            if urlText.isEmpty {
                pasteFromClipboard()
            } else {
                validateURL(urlText)
            }
        }
    }
    
    private func pasteFromClipboard() {
        if let clipboardResult = YouTubeURLParser.checkClipboard() {
            urlText = clipboardResult.originalInput
            parsedResult = clipboardResult
        } else if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
            urlText = str
            validateURL(str)
        }
    }
    
    private func validateURL(_ text: String) {
        parsedResult = YouTubeURLParser.parse(text)
    }
}
