//
//  MetadataInspectorSheet.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.12.21.
//

import SwiftUI
import AppKit

/// A read-only inspector-style sheet that shows the *raw* metadata dump text.
///
/// Notes:
/// - This view intentionally does *not* render the same friendly fields shown in the right inspector.
/// - It is meant to display the unabridged TagLib-derived text (property map / frames / atoms, etc.).
struct MetadataInspectorSheet: View {
    let fileURL: URL
    let dumpText: String

    @Environment(\.dismiss) private var dismiss

    private var fileName: String { fileURL.lastPathComponent }
    private var filePath: String { fileURL.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            content
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 520)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Copy") {
                    copyToPasteboard(dumpText)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy the raw metadata text")

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Raw Metadata")
                .font(.title2)
                .fontWeight(.semibold)

            Text(fileName)
                .font(.headline)

            HStack(spacing: 6) {
                Text(filePath)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                Spacer(minLength: 12)

                Button {
                    copyToPasteboard(filePath)
                } label: {
                    Text("Copy Path")
                }
                .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if dumpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No raw metadata was returned.")
                    .font(.headline)
                Text("If this is unexpected, verify the file is an MP3 and that TagLib can open it.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                Text(dumpText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary.opacity(0.35))
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}

struct MetadataInspectorSheet_Previews: PreviewProvider {
    static var previews: some View {
        MetadataInspectorSheet(
            fileURL: URL(fileURLWithPath: "/Users/lloyd/Music/Test/01 - Example.mp3"),
            dumpText: """
[TagLib::PropertyMap]
TIT2 = Carpe Diem
TPE1 = Maurice Jarre
TALB = Dead Poets Society
TCON = Soundtrack
TYER = 1990
COMM = (empty)

[ID3v2 Frames]
TIT2: Carpe Diem
TPE1: Maurice Jarre
TALB: Dead Poets Society
"""
        )
    }
}
