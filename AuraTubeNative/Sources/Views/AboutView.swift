import SwiftUI
import AppKit

@MainActor
final class AboutViewModel: ObservableObject {
    @Published var isHoveringCheckUpdate: Bool = false
    @Published var isHoveringClose: Bool = false
}

public struct AboutView: View {
    @ObservedObject private var updateService = UpdateService.shared
    @StateObject private var vm = AboutViewModel()
    var onClose: () -> Void
    
    public init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }
    
    public var body: some View {
        ZStack {
            // Dark elegant acrylic background
            Color(red: 0.10, green: 0.10, blue: 0.12)
                .ignoresSafeArea()
            
            // Soft subtle ambient glow behind the icon
            VStack {
                RadialGradient(
                    colors: [
                        Color(red: 0.95, green: 0.15, blue: 0.22).opacity(0.22),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 120
                )
                .frame(width: 240, height: 160)
                .offset(y: -15)
                
                Spacer()
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header (Single macOS-style close button on top-left)
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.36, blue: 0.32))
                            .frame(width: 12, height: 12)
                        
                        if vm.isHoveringClose {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .black))
                                .foregroundColor(Color(red: 0.35, green: 0.05, blue: 0.05))
                        }
                    }
                    .contentShape(Circle())
                    .onTapGesture { onClose() }
                    .onHover { vm.isHoveringClose = $0 }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .background(
                    Button("") { onClose() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .opacity(0)
                )
                
                Spacer(minLength: 4)
                
                // App Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.15, blue: 0.22).opacity(0.28))
                        .frame(width: 74, height: 74)
                        .blur(radius: 10)
                        .offset(y: 3)
                    
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 70, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 70, height: 70)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                }
                
                // Name & Version
                VStack(spacing: 5) {
                    Text("AuraTube")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Phiên bản \(updateService.currentVersion) (\(updateService.currentBuild))")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(white: 0.6))
                }
                .padding(.top, 12)
                
                Spacer(minLength: 12)
                
                // Update Button
                Button(action: {
                    onClose()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        UpdateService.shared.scanForUpdates(isUserInitiated: true)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Kiểm tra bản cập nhật...")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.15, blue: 0.25),
                                Color(red: 0.80, green: 0.08, blue: 0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: Color.red.opacity(vm.isHoveringCheckUpdate ? 0.35 : 0.15), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .onHover { vm.isHoveringCheckUpdate = $0 }
                
                Spacer(minLength: 10)
                
                // Clean Footer
                Text("© 2026 AuraTube")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(white: 0.35))
                    .padding(.bottom, 14)
            }
        }
        .frame(width: 320, height: 310)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .preferredColorScheme(.dark)
    }
}
