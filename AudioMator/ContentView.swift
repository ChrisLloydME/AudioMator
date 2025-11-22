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
        if let id = selectedID {
            return viewModel.files.first(where: { $0.id == id })
        }
        return nil
    }
    
    var body: some View {
        NavigationView {
            // 左侧：列表 + 添加按钮
            VStack {
                Button("添加音频文件…") {
                    viewModel.addFiles()
                }
                .padding()
                
                List(selection: $selectedID) {
                    ForEach(viewModel.files) { file in
                        Text(file.url.lastPathComponent)
                            .font(.body)
                    }
                }
            }
            .frame(minWidth: 250)
            
            // 右侧：显示元数据
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
                Text("选择左侧列表中的音频文件以查看元数据")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
