//
//  InspectorPopup.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.12.18.
//

import SwiftUI

struct InspectorPopup<Content: View>: View {
    let title: String
    let subtitle: String?
    @Binding var isPresented: Bool

    // 你可以按需要调整
    let width: CGFloat
    let minHeight: CGFloat

    private let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        isPresented: Binding<Bool>,
        width: CGFloat = 520,
        minHeight: CGFloat = 520,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isPresented = isPresented
        self.width = width
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        ZStack {
            // Background dim
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Card
            VStack(spacing: 0) {
                header

                Divider().opacity(0.5)

                content
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: width)
            .frame(minHeight: minHeight)
            .background(
                // macOS 13+ 玻璃质感
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 14)
            .padding(24)
            .transition(.scale(scale: 0.98).combined(with: .opacity))
        }
        .animation(.easeInOut(duration: 0.16), value: isPresented)
        .onExitCommand { dismiss() } // ESC 关闭（macOS）
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))  // “Edit Album”更大更符合 HIG 的感觉
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close")
        }
        .padding(16)
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.16)) {
            isPresented = false
        }
    }
}
