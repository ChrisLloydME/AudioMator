//
//  AudioViewModel.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import Combine

@MainActor
final class AudioViewModel: ObservableObject {
    // 当前加载到中间列表里的所有音频文件
    @Published var files: [AudioFile] = []
    // 中间列表的选中项（支持多选，但目前单文件编辑只用第一个）
    @Published var selectedAudioIDs: Set<UUID> = []
    // 右侧 Inspector 绑定的单文件编辑模型
    @Published var edit: SingleFileEditModel?

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
}
