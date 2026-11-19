// SPDX-License-Identifier: GPL-2.0-only
// Ps3p: installing without the file picker. Files put in Files › On My iPhone › Ps3p › Install
// (or shared to Ps3p with "Open in"/the share sheet, which lands them in Inbox) are listed on
// the Install tab with a one-tap Install button.

import Foundation
import SwiftUI

enum Ps3pInstallInbox {
    static let extensions: Set<String> = ["pkg", "rap", "edat", "pup"]
    static let changed = Notification.Name("Ps3pInstallInboxChanged")

    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var installFolder: URL { documents.appendingPathComponent("Install", isDirectory: true) }
    private static var inboxFolder: URL { documents.appendingPathComponent("Inbox", isDirectory: true) }

    /// Makes the Install folder so it shows up in the Files app straight away.
    static func prepare() {
        let folder = installFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let readme = folder.appendingPathComponent("Put PKG, RAP, EDAT and PS3UPDAT.PUP files here.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            try? Data("Files placed in this folder appear on Ps3p's Install tab.\n".utf8).write(to: readme)
        }
    }

    static func pending() -> [URL] {
        let manager = FileManager.default
        return [installFolder, inboxFolder].flatMap { folder in
            (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        }
        .filter { extensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// A file opened in Ps3p from another app: moved (or copied) into the Install folder.
    @discardableResult
    static func receive(_ url: URL) -> Bool {
        guard url.isFileURL, extensions.contains(url.pathExtension.lowercased()) else { return false }
        prepare()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let destination = installFolder.appendingPathComponent(url.lastPathComponent)
        let manager = FileManager.default
        if url.standardizedFileURL.deletingLastPathComponent() != installFolder.standardizedFileURL {
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

/// The card on the Install tab listing files waiting in the Ps3p folder.
struct Ps3pInboxCard: View {
    let busy: Bool
    let install: ([URL]) async -> Bool

    @State private var files: [URL] = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ps3p folder", systemImage: "folder.fill")
                .font(.headline)
            if files.isEmpty {
                Text("If the picker won't open a file, put it in Files › On My iPhone › Ps3p › Install and it appears here.")
                    .font(.footnote)
                    .foregroundStyle(OverlayTheme.textSecondary)
            } else {
                ForEach(files, id: \.self) { file in
                    HStack {
                        Image(systemName: icon(for: file)).foregroundStyle(OverlayTheme.textSecondary)
                        Text(file.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(size(of: file)).font(.caption).foregroundStyle(OverlayTheme.textSecondary)
                    }
                }
                Button {
                    let batch = files
                    Ps3pAudio.shared.play(.decide)
                    Task {
                        if await install(batch) {
                            Ps3pAudio.shared.play(.ok)
                            // The installed copy lives inside the emulator now; free the space.
                            Ps3pInstallInbox.remove(batch)
                        }
                        reload()
                    }
                } label: {
                    Text(files.count == 1 ? "Install" : "Install all (\(files.count))").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy)
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

    private func reload() {
        Ps3pInstallInbox.prepare()
        files = Ps3pInstallInbox.pending()
    }

    private func icon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pkg": "shippingbox.fill"
        case "pup": "cpu.fill"
        default: "key.fill"
        }
    }

    private func size(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
