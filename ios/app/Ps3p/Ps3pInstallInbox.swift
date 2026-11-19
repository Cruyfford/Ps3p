// SPDX-License-Identifier: GPL-2.0-only
// Ps3p: installing without the file picker. Files put in Files › On My iPhone › Ps3p › Install
// (or shared to Ps3p with "Open in"/the share sheet, which lands them in Inbox) are listed on
// the Install tab with a one-tap Install button.

import Foundation
import SwiftUI

enum Ps3pInstallInbox {
    static let extensions: Set<String> = ["pkg", "rap", "edat", "pup"]
    static let changed = Notification.Name("Ps3pInstallInboxChanged")

    /// Ps3p's own folders in Files › On My iPhone › Ps3p.
    enum Kind: String, CaseIterable {
        case pkg = "PKG", rap = "RAP", firmware = "Firmware"

        var extensions: Set<String> {
            switch self {
            case .pkg: ["pkg"]
            case .rap: ["rap", "edat"]
            case .firmware: ["pup"]
            }
        }

        var folder: URL { Ps3pInstallInbox.documents.appendingPathComponent(rawValue, isDirectory: true) }

        static func of(_ url: URL) -> Kind? {
            let ext = url.pathExtension.lowercased()
            return allCases.first { $0.extensions.contains(ext) }
        }
    }

    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    // Older builds used one Install folder; shared files land in Inbox. Both are still read.
    private static var legacyFolders: [URL] {
        ["Install", "Inbox"].map { documents.appendingPathComponent($0, isDirectory: true) }
    }

    /// Makes the folders so they show up in the Files app straight away.
    static func prepare() {
        for kind in Kind.allCases {
            try? FileManager.default.createDirectory(at: kind.folder, withIntermediateDirectories: true)
        }
    }

    /// Files waiting, by kind.
    static func pending() -> [Kind: [URL]] {
        let manager = FileManager.default
        let folders = Kind.allCases.map(\.folder) + legacyFolders
        let urls = folders.flatMap { (try? manager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
        var result: [Kind: [URL]] = [:]
        for url in urls {
            guard let kind = Kind.of(url) else { continue }
            result[kind, default: []].append(url)
        }
        for kind in result.keys {
            result[kind]?.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        return result
    }

    /// A file opened in Ps3p from another app: moved (or copied) into the folder for its kind.
    @discardableResult
    static func receive(_ url: URL) -> Bool {
        guard url.isFileURL, let kind = Kind.of(url) else { return false }
        prepare()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let destination = kind.folder.appendingPathComponent(url.lastPathComponent)
        let manager = FileManager.default
        if url.standardizedFileURL.deletingLastPathComponent() != kind.folder.standardizedFileURL {
            try? manager.removeItem(at: destination)
            if (try? manager.moveItem(at: url, to: destination)) == nil {
                try? manager.copyItem(at: url, to: destination)
            }
        }
        NotificationCenter.default.post(name: changed, object: nil)
        return true
    }

    static func remove(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

/// The card on the Install tab: files waiting in the PKG, RAP and Firmware folders, all installed with one tap.
struct Ps3pInboxCard: View {
    let busy: Bool
    let install: ([URL]) async -> Bool

    @State private var files: [Ps3pInstallInbox.Kind: [URL]] = [:]
    @State private var working = false
    @Environment(\.scenePhase) private var scenePhase

    private var total: Int { files.values.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ps3p folders", systemImage: "folder.fill")
                .font(.headline)
            Text("Files › On My iPhone › Ps3p: put games in PKG, licences in RAP, firmware in Firmware.")
                .font(.footnote)
                .foregroundStyle(OverlayTheme.textSecondary)

            ForEach(Ps3pInstallInbox.Kind.allCases, id: \.self) { kind in
                let list = files[kind] ?? []
                if !list.isEmpty {
                    DisclosureGroup {
                        ForEach(list, id: \.self) { file in
                            HStack {
                                Text(file.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(size(of: file)).font(.caption).foregroundStyle(OverlayTheme.textSecondary)
                            }
                            .font(.subheadline)
                        }
                    } label: {
                        Label("\(kind.rawValue) (\(list.count))", systemImage: icon(kind))
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }

            if total > 0 {
                Button {
                    Ps3pAudio.shared.play(.decide)
                    Task { await installAll() }
                } label: {
                    HStack {
                        if working { ProgressView().tint(.white) }
                        Text(working ? "Installing…" : "Install all (\(total))")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy || working)
            } else {
                Text("Nothing waiting.")
                    .font(.footnote)
                    .foregroundStyle(OverlayTheme.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
        .padding(.horizontal)
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .onReceive(NotificationCenter.default.publisher(for: Ps3pInstallInbox.changed)) { _ in reload() }
    }

    /// Firmware first, then licences, then games, so each game is licensed as it lands.
    private func installAll() async {
        working = true
        defer { working = false; reload() }
        var allOK = true
        for kind in [Ps3pInstallInbox.Kind.firmware, .rap, .pkg] {
            let batch = files[kind] ?? []
            guard !batch.isEmpty else { continue }
            if await install(batch) {
                // The installed copy lives inside the emulator now; free the space.
                Ps3pInstallInbox.remove(batch)
            } else {
                allOK = false
            }
        }
        Ps3pAudio.shared.play(allOK ? .ok : .error)
    }

    private func reload() {
        Ps3pInstallInbox.prepare()
        files = Ps3pInstallInbox.pending()
    }

    private func icon(_ kind: Ps3pInstallInbox.Kind) -> String {
        switch kind {
        case .pkg: "shippingbox.fill"
        case .rap: "key.fill"
        case .firmware: "cpu.fill"
        }
    }

    private func size(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
