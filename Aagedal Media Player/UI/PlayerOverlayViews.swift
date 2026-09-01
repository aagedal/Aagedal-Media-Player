// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Reusable overlays displayed above the main player content.

import AppKit
import SwiftUI

struct MediaOperationFeedbackOverlay: View {
    @ObservedObject var controller: PlayerController

    var body: some View {
        Group {
            if controller.screenshotState.isVisible {
                screenshotOverlay
            }
            if controller.trimExportState.isVisible {
                trimExportOverlay
            }
        }
    }

    @ViewBuilder
    private var screenshotOverlay: some View {
        switch controller.screenshotState {
        case .idle:
            EmptyView()
        case .saving:
            operationOverlay(statusText: "Saving\u{2026}", showSpinner: true)
        case .succeeded(let url):
            operationOverlay(
                statusIcon: "checkmark.circle.fill",
                iconColor: .green,
                statusText: "Screenshot saved.",
                completedURL: url
            )
        case .failed(let message):
            errorOverlay(message) { controller.dismissScreenshotFeedback() }
        }
    }

    @ViewBuilder
    private var trimExportOverlay: some View {
        switch controller.trimExportState {
        case .idle:
            EmptyView()
        case .warning(let message):
            warningOverlay(message)
        case .preparing:
            operationOverlay(
                statusText: "Preparing export\u{2026}",
                showSpinner: true,
                onCancel: { controller.cancelExport() }
            )
        case .exporting(let progress):
            operationOverlay(
                statusText: "Exporting \(Int(progress * 100))%",
                progress: progress,
                onCancel: { controller.cancelExport() }
            )
        case .cancelling:
            operationOverlay(statusIcon: nil, statusText: "Cancelling\u{2026}", showSpinner: true)
        case .cancelled:
            operationOverlay(
                statusIcon: "xmark.circle.fill",
                iconColor: .orange,
                statusText: "Export cancelled."
            )
        case .succeeded(let url):
            operationOverlay(
                statusIcon: "checkmark.circle.fill",
                iconColor: .green,
                statusText: "Trimmed file saved.",
                completedURL: url
            )
        case .failed(let message):
            errorOverlay(message) { controller.dismissTrimExportFeedback() }
        }
    }

    private func operationOverlay(
        statusIcon: String? = nil,
        iconColor: Color = .green,
        statusText: String,
        showSpinner: Bool = false,
        progress: Double? = nil,
        onCancel: (() -> Void)? = nil,
        completedURL: URL? = nil
    ) -> some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                if showSpinner {
                    ProgressView()
                        .controlSize(.small)
                }
                if let statusIcon {
                    Image(systemName: statusIcon)
                        .foregroundStyle(iconColor)
                }
                Text(statusText)
                if let onCancel {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 18, height: 18)
                            .background(.white.opacity(0.15), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel export")
                    .accessibilityLabel("Cancel export")
                }
                if let completedURL {
                    completionActions(for: completedURL)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.7), in: .capsule)
            .overlay {
                if let progress {
                    ProgressCapsuleBorder(progress: progress)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .animation(.linear(duration: 0.2), value: progress)
                }
            }
            .padding(.bottom, 80)
        }
        .transition(.opacity)
    }

    private func completionActions(for url: URL) -> some View {
        Menu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Open") {
                NSWorkspace.shared.open(url)
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.white.opacity(0.8))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("File actions")
        .accessibilityLabel("File actions")
        .accessibilityHint("Reveal, open, or copy the saved file path.")
    }

    private func warningOverlay(_ message: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.7), in: .capsule)
            .padding(.bottom, 80)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    private func errorOverlay(
        _ message: String,
        onDismiss: @escaping () -> Void
    ) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .lineLimit(2)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss error")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.8), in: .capsule)
            .padding(.bottom, 80)
        }
        .transition(.opacity)
    }
}

private struct ProgressCapsuleBorder: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = rect.height / 2
        let straightLength = rect.width - 2 * radius
        let semicircleLength = .pi * radius
        let totalLength = 2 * semicircleLength + 2 * straightLength
        let target = totalLength * min(max(progress, 0), 1)

        var path = Path()
        var drawn: CGFloat = 0

        let firstLength = straightLength / 2
        guard drawn < target else { return path }
        let firstDrawn = min(firstLength, target - drawn)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + firstDrawn, y: rect.minY))
        drawn += firstDrawn

        guard drawn < target else { return path }
        let secondDrawn = min(semicircleLength, target - drawn)
        let rightCenter = CGPoint(x: rect.maxX - radius, y: rect.midY)
        path.addArc(
            center: rightCenter,
            radius: radius,
            startAngle: .radians(-.pi / 2),
            endAngle: .radians(-.pi / 2 + secondDrawn / radius),
            clockwise: false
        )
        drawn += secondDrawn

        guard drawn < target else { return path }
        let thirdDrawn = min(straightLength, target - drawn)
        path.addLine(to: CGPoint(x: rect.maxX - radius - thirdDrawn, y: rect.maxY))
        drawn += thirdDrawn

        guard drawn < target else { return path }
        let fourthDrawn = min(semicircleLength, target - drawn)
        let leftCenter = CGPoint(x: rect.minX + radius, y: rect.midY)
        path.addArc(
            center: leftCenter,
            radius: radius,
            startAngle: .radians(.pi / 2),
            endAngle: .radians(.pi / 2 + fourthDrawn / radius),
            clockwise: false
        )
        drawn += fourthDrawn

        guard drawn < target else { return path }
        let fifthDrawn = min(straightLength / 2, target - drawn)
        path.addLine(to: CGPoint(x: rect.minX + radius + fifthDrawn, y: rect.minY))
        return path
    }
}

struct UpdateAvailableBanner: View {
    @ObservedObject var updateChecker: UpdateChecker
    @Binding var isDismissed: Bool

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.white)

                Text("Version \(updateChecker.latestVersion) available")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)

                Button {
                    if updateChecker.isHomebrewInstall {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            UpdateChecker.homebrewUpgradeCommand,
                            forType: .string
                        )
                    } else {
                        updateChecker.openDownloadAsset()
                    }
                } label: {
                    Text(updateChecker.isHomebrewInstall ? "Copy brew Command" : "Download")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.2), in: .capsule)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { isDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Dismiss update")
                .accessibilityLabel("Dismiss update")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.85), in: .capsule)
            .padding(.top, 36)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .allowsHitTesting(true)
    }
}
