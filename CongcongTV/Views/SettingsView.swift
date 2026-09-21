import SwiftUI

/// 设置页：配置 URL / 粘贴配置 / 恢复默认，并展示可用站点与引擎状态。
struct SettingsView: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var engine: EngineManager
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var pastedText = ""
    @State private var showPasteSheet = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("配置源") {
                TextField("配置地址 https://…", text: $urlText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                HStack {
                    Button("载入远程配置") {
                        Task {
                            let ok = await store.loadRemote(urlText)
                            message = ok ? "✅ 已加载远程配置" : "❌ 加载失败：\(store.lastError ?? "")"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(urlText.isEmpty)

                    Button("恢复默认") {
                        urlText = ConfigStore.defaultConfigURL
                        _ = store.loadBuiltin()
                        message = "已恢复为内置 movie2 配置"
                    }
                    .buttonStyle(.bordered)
                }

                Button("粘贴整段配置 JSON") {
                    showPasteSheet = true
                }
                .buttonStyle(.bordered)

                if let msg = message {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                LabeledContent("当前来源", value: sourceLabel)
                LabeledContent("站点数", value: "\(store.config.sites.count)")
                LabeledContent("可用 JS 源", value: "\(store.config.usableSites.count)")
                LabeledContent("直播源", value: "\(store.config.lives.count)")
            }

            Section("可用站点（JS 引擎）") {
                let usable = store.config.usableSites
                if usable.isEmpty {
                    Text("无可用站点").foregroundColor(.secondary)
                } else {
                    ForEach(usable) { s in
                        LabeledContent(s.name, value: engine.prepared[s.key] != nil ? "已就绪" : "准备中")
                            .foregroundColor(engine.prepared[s.key] != nil ? .primary : .secondary)
                    }
                }
            }

            Section("关于") {
                LabeledContent("应用", value: "丛丛影视 CactusTV")
                Text("基于原有 movie2 配置解析，Android jar 源在 iOS 上仅作展示")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if urlText.isEmpty {
                urlText = store.userConfigURL
            }
        }
        .sheet(isPresented: $showPasteSheet) {
            NavigationStack {
                VStack(alignment: .leading) {
                    TextEditor(text: $pastedText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                    Text("粘贴完整的配置 JSON（sites/lives 字段原样使用）")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()
                .navigationTitle("粘贴配置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showPasteSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("载入") {
                            let ok = store.loadPasted(pastedText)
                            message = ok ? "✅ 已载入粘贴配置" : "❌ 解析失败：\(store.lastError ?? "")"
                            showPasteSheet = false
                        }
                        .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var sourceLabel: String {
        switch store.lastLoadedFrom {
        case .builtin: return "内置配置"
        case .remote: return "远程配置"
        case .paste: return "粘贴配置"
        case .none: return "未加载"
        }
    }
}
