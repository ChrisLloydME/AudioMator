//
//  AudioViewModel.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import Combine

struct MetadataWriteSuccessHUD: Identifiable, Equatable {
    let id = UUID()
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
    @Published var metadataWriteSuccessHUD: MetadataWriteSuccessHUD?

    private var metadataWriteSuccessDismissTask: Task<Void, Never>?
    private var pendingMetadataWriteSuccessHUDs: [MetadataWriteSuccessHUD] = []

    deinit {
        metadataWriteSuccessDismissTask?.cancel()
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
        let hud = MetadataWriteSuccessHUD(
            title: "Metadata Written",
            subtitle: fileName
        )
        pendingMetadataWriteSuccessHUDs.append(hud)

        guard metadataWriteSuccessHUD == nil else { return }
        showNextMetadataWriteSuccessHUD()
    }

    private func showNextMetadataWriteSuccessHUD() {
        guard metadataWriteSuccessHUD == nil, !pendingMetadataWriteSuccessHUDs.isEmpty else { return }

        metadataWriteSuccessDismissTask?.cancel()

        let hud = pendingMetadataWriteSuccessHUDs.removeFirst()
        metadataWriteSuccessHUD = hud

        metadataWriteSuccessDismissTask = Task { [weak self, hudID = hud.id] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.metadataWriteSuccessHUD?.id == hudID else { return }
                self.metadataWriteSuccessHUD = nil
            }

            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.showNextMetadataWriteSuccessHUD()
            }
        }
    }
}
