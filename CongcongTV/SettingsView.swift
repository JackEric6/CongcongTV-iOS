import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var isReloading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("配置地址") {
                    TextField("TVBox JSON 地址", text: $address, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        reload()
                    } label: {
                        Label(isReloading ? "正在加载" : "保存并加载", systemImage: "arrow.clockwise")
                    }
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isReloading)
                }

                Section("当前状态") {
                    LabeledContent("站点数量", value: "\(model.sites.count)")
                    LabeledContent("当前站点", value: model.selectedSite?.name ?? "未选择")
                    Text(model.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(role: .destructive) {
                        model.clearCache()
                    } label: {
                        Label("清除配置缓存", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { address = model.configURL }
        }
    }

    private func reload() {
        isReloading = true
        Task {
            await model.loadConfig(address: address)
            isReloading = false
        }
    }
}
