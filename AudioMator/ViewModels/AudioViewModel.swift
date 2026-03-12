//
//  AudioViewModel.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import Combine

private let metadataWriteSuccessHUDDuration: Duration = .seconds(2.3)

enum MetadataWriteHUDStyle: Equatable {
    case success
    case warning
    case failure
}

struct MetadataWriteHUD: Identifiable, Equatable {
    let id = UUID()
    let style: MetadataWriteHUDStyle
    let title: String
    let subtitle: String
}

@MainActor
final class AudioViewModel: ObservableObject {
    // 当前加载到中间列表里的所有音频文件
    @Published var files: [AudioFile] = []
    // 中间列表的选中项（支持多选，但目前单文件编辑只用第一个）
    @Published var selectedAudioIDs: Set<UUID> = []
    // 右侧 Inspector 绑定的单文件编辑模型
    @Published var edit: SingleFileEditModel?
    @Published var metadataWriteHUD: MetadataWriteHUD?

    private var metadataWriteHUDDismissTask: Task<Void, Never>?
    private var pendingMetadataWriteHUDs: [MetadataWriteHUD] = []

    deinit {
        metadataWriteHUDDismissTask?.cancel()
    }

    // MARK: - 选中与编辑同步

    /// 当中间列表的选中项变化时调用，保持右侧 Inspector 内容与当前文件同步
    func updateEditForSelection() {
        guard
            let id = selectedAudioIDs.first,
            let file = files.first(where: { $0.id == id })
        else {
            edit = nil
            return
        }

        edit = SingleFileEditModel(from: file)
    }

    /// 放弃当前编辑，恢复为磁盘上的最新标签
    func cancelEditing() {
        updateEditForSelection()
    }

    func presentMetadataWriteSuccess(for fileName: String) {
        enqueueMetadataWriteHUD(
            style: .success,
            title: "Saved to Disk",
            subtitle: fileName
        )
    }

    func presentMetadataWriteWarning(title: String, subtitle: String) {
        enqueueMetadataWriteHUD(
            style: .warning,
            title: title,
            subtitle: subtitle
        )
    }

    func presentMetadataWriteFailure(for fileName: String, reason: String) {
        enqueueMetadataWriteHUD(
            style: .failure,
            title: "Save Failed",
            subtitle: [fileName, reason]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        )
    }

    private func enqueueMetadataWriteHUD(
        style: MetadataWriteHUDStyle,
        title: String,
        subtitle: String
    ) {
        let hud = MetadataWriteHUD(
            style: style,
            title: title,
            subtitle: subtitle
        )
        pendingMetadataWriteHUDs.append(hud)

        guard metadataWriteHUD == nil else { return }
        showNextMetadataWriteHUD()
    }

    private func showNextMetadataWriteHUD() {
        guard metadataWriteHUD == nil, !pendingMetadataWriteHUDs.isEmpty else { return }

        metadataWriteHUDDismissTask?.cancel()

        let hud = pendingMetadataWriteHUDs.removeFirst()
        metadataWriteHUD = hud

        metadataWriteHUDDismissTask = Task { [weak self, hudID = hud.id] in
            try? await Task.sleep(for: metadataWriteSuccessHUDDuration)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.metadataWriteHUD?.id == hudID else { return }
                self.metadataWriteHUD = nil
            }

            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.showNextMetadataWriteHUD()
            }
        }
    }
}
