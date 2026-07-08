import SwiftUI

struct QQMailImportSheet: View {
    @Binding var isImporting: Bool

    let onImported: (QQMailImportResult) -> Void
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var provider = QQMailCredentialStore.shared.selectedProvider
    @State private var emailAddress = QQMailCredentialStore.shared.emailAddress(for: QQMailCredentialStore.shared.selectedProvider) ?? ""
    @State private var authCode = QQMailCredentialStore.shared.authCode(for: QQMailCredentialStore.shared.selectedProvider) ?? ""
    @State private var daysBack = 3
    @State private var skipTravelPDF = true
    @State private var statusText = "默认下载近 3 日邮件中的 PDF 和 ZIP 附件。"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("从邮箱导入发票")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(provider.helpText)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("邮箱类型")
                    Picker("邮箱类型", selection: $provider) {
                        ForEach(MailProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 320)
                }

                GridRow {
                    Text("邮箱地址")
                    TextField(provider.emailPlaceholder, text: $emailAddress)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }

                GridRow {
                    Text("授权码")
                    SecureField(provider.authCodePlaceholder, text: $authCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }

                GridRow {
                    Text("邮件时间")
                    Stepper("\(daysBack) 日内", value: $daysBack, in: 1...30)
                }

                GridRow {
                    Text("筛选规则")
                    Toggle("剔除行程单、行程明细类 PDF", isOn: $skipTravelPDF)
                }
            }

            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("清除记忆") {
                    QQMailCredentialStore.shared.clear(provider: provider)
                    emailAddress = ""
                    authCode = ""
                    statusText = "已清除本机保存的 \(provider.displayName) 信息。"
                }
                .disabled(isImporting)

                Button("取消") {
                    dismiss()
                }
                .disabled(isImporting)

                Spacer()

                Button {
                    importFromMail()
                } label: {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("开始下载", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting || emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authCode.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onChange(of: provider) { newProvider in
            QQMailCredentialStore.shared.saveSelectedProvider(newProvider)
            emailAddress = QQMailCredentialStore.shared.emailAddress(for: newProvider) ?? ""
            authCode = QQMailCredentialStore.shared.authCode(for: newProvider) ?? ""
            statusText = "默认下载近 3 日邮件中的 PDF 和 ZIP 附件。"
        }
    }

    private func importFromMail() {
        isImporting = true
        statusText = "正在连接 \(provider.displayName)..."

        let request = QQMailImportRequest(
            provider: provider,
            emailAddress: emailAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            authCode: authCode,
            daysBack: daysBack,
            skipTravelPDF: skipTravelPDF
        )

        QQMailCredentialStore.shared.saveSelectedProvider(provider)
        QQMailCredentialStore.shared.save(provider: provider, emailAddress: request.emailAddress, authCode: request.authCode)

        Task {
            do {
                let result = try await QQMailImporter().importRecentInvoices(request: request) { status in
                    Task { @MainActor in
                        statusText = status
                    }
                }

                await MainActor.run {
                    isImporting = false
                    dismiss()
                    onImported(result)
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    onError("邮箱导入失败：\(error.localizedDescription)")
                }
            }
        }
    }
}
