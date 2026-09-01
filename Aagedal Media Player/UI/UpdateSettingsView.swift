// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Sparkle
import SwiftUI

struct UpdateSettingsView: View {
    @StateObject private var checker = UpdateChecker.shared
    @StateObject private var sparkleUpdater = SparkleUpdater.shared

    var body: some View {
        Form {
            Section("Current Version") {
                LabeledContent("Version") {
                    Text(checker.currentVersion)
                        .monospacedDigit()
                }
            }

            Section("Update Check") {
                if sparkleUpdater.isActive {
                    SparkleUpdateControls(
                        updater: sparkleUpdater.updater,
                        checkNow: { sparkleUpdater.controller.checkForUpdates(nil) }
                    )
                } else {
                    FallbackUpdateControls(checker: checker)
                }
            }

            if checker.isHomebrewInstall {
                Section {
                    HomebrewUpdateHintView(highlight: checker.updateAvailable)
                }
            } else if !sparkleUpdater.isActive, checker.updateAvailable, !checker.latestVersion.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Version \(checker.latestVersion) Available")
                                .fontWeight(.medium)
                            Text("You are running \(checker.currentVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Download") {
                            checker.openDownloadAsset()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Settings controls bound to Sparkle's `SPUUpdater`. `SPUUpdater` exposes its
/// state via KVO rather than `@Published`, so the toggles use direct
/// `Binding` closures — changes coming from Sparkle's own UI won't live-refresh
/// this view, but user input in Settings persists immediately.
private struct SparkleUpdateControls: View {
    let updater: SPUUpdater
    let checkNow: () -> Void

    private static let intervalChoices: [(label: String, seconds: TimeInterval)] = [
        ("Daily", 86_400),
        ("Weekly", 604_800),
        ("Monthly", 2_592_000)
    ]

    var body: some View {
        Toggle("Automatically check for updates", isOn: Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        ))

        if updater.automaticallyChecksForUpdates {
            Picker("Check frequency", selection: Binding(
                get: { closestInterval(to: updater.updateCheckInterval) },
                set: { updater.updateCheckInterval = $0 }
            )) {
                ForEach(Self.intervalChoices, id: \.seconds) { choice in
                    Text(choice.label).tag(choice.seconds)
                }
            }

            Toggle("Install updates automatically", isOn: Binding(
                get: { updater.automaticallyDownloadsUpdates },
                set: { updater.automaticallyDownloadsUpdates = $0 }
            ))
            .help("Downloads new releases in the background and installs them on next launch.")
        }

        HStack {
            Spacer()
            Button("Check Now", action: checkNow)
        }
    }

    private func closestInterval(to seconds: TimeInterval) -> TimeInterval {
        Self.intervalChoices
            .min(by: { abs($0.seconds - seconds) < abs($1.seconds - seconds) })?
            .seconds ?? 604_800
    }
}

private struct FallbackUpdateControls: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        LabeledContent("Last Checked") {
            if let date = checker.lastChecked {
                Text(date, style: .relative)
                    .foregroundStyle(.secondary)
                + Text(" ago")
                    .foregroundStyle(.secondary)
            } else {
                Text("Never")
                    .foregroundStyle(.secondary)
            }
        }

        HStack {
            switch checker.result {
            case .checking:
                ProgressView()
                    .controlSize(.small)
                Text("Checking\u{2026}")
                    .foregroundStyle(.secondary)
            case .upToDate:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Up to date")
                    .foregroundStyle(.secondary)
            case .updateAvailable(let release):
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text("Version \(release.version) available")
                    .foregroundStyle(.secondary)
            case .failed(let failure):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(failure.message)
                    .foregroundStyle(.secondary)
            case .notChecked:
                EmptyView()
            }

            Spacer()

            Button(retryButtonTitle) {
                Task { await checker.checkNow() }
            }
            .disabled(checker.isChecking)
        }
    }

    private var retryButtonTitle: String {
        guard case .failed(let failure) = checker.result, failure.isRetryable else {
            return "Check Now"
        }
        return "Retry"
    }
}

private struct HomebrewUpdateHintView: View {
    let highlight: Bool
    private var command: String { UpdateChecker.homebrewUpgradeCommand }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Managed by Homebrew", systemImage: "shippingbox")
                .font(.headline)

            Text(highlight
                 ? "An update is available. Install it through Homebrew to keep brew's records consistent:"
                 : "This copy was installed via Homebrew. To update, run:")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(highlight ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(6)

                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
                .accessibilityLabel("Copy command to clipboard")
            }
        }
        .padding(.vertical, 4)
    }
}
