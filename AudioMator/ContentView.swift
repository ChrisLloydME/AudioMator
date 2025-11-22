//
//  ContentView.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AudioViewModel()
    @State private var selectedID: AudioFile.ID?
    
    private var selectedFile: AudioFile? {
        viewModel.files.first { $0.id == selectedID }
    }
    
    var body: some View {
        NavigationView {
            // 左侧...
            VStack {
                Button("添加音频文件…") { viewModel.addFiles() }
                    .padding()

                List(selection: $selectedID) {
                    ForEach(viewModel.files) { file in
                        Text(file.url.lastPathComponent)
                    }
                }
            }
            .frame(minWidth: 250)

            // 右侧...
            Group {
                if let file = selectedFile {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("文件名：\(file.url.lastPathComponent)")
                            .font(.headline)
                        Text("标题：\(file.title ?? "（无）")")
                        Text("艺术家：\(file.artist ?? "（无）")")
                        Text("专辑：\(file.album ?? "（无）")")
                        Spacer()
                    }
                    .padding()
                } else {
                    Text("选择左侧音频文件以查看元数据")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        
        // ⭐ 必须加一个空 toolbar 来启用 unified 样式
        .toolbar {
            ToolbarItem(placement: .automatic) {
                EmptyView()
            }
        }
    }
}

#Preview {
    ContentView()
}
