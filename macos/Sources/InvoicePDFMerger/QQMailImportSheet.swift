import SwiftUI

struct QQMailImportSheet: View {
    @Binding var isImporting: Bool

    let onImported: (QQMailImportResult) -> Void
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var emailAddress = QQMailCredentialStore.shared.emailAddress ?? ""
    @State private var authCode = QQMailCredentialStore.shared.authCode ?? ""
    @State private var daysBack = 3
    @State private var skipTravelPDF = true
    @State private var statusText = "默认下载近 3 日邮件中的 PDF 和 ZIP 附件。"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("从 QQ 邮箱导入发票")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("请使用 QQ 邮箱开启 IMAP 后生成的授权码，不要填写 QQ 登录密码。")
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("邮箱地址")
                    TextField("例如 name@qq.com", text: $emailAddress)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }

                GridRow {
                    Text("授权码")
                    SecureField("QQ 邮箱授权码", text: $authCode)
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
                    QQMailCredentialStore.shared.clear()
                    emailAddress = ""
                    authCode = ""
                    statusText = "已清除本机保存的 QQ 邮箱信息。"
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
    }

    private func importFromMail() {
        isImporting = true
        statusText = "正在连接 QQ 邮箱..."

        let request = QQMailImportRequest(
            emailAddress: emailAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            authCode: authCode,
            daysBack: daysBack,
            skipTravelPDF: skipTravelPDF
        )

        QQMailCredentialStore.shared.save(emailAddress: request.emailAddress, authCode: request.authCode)

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
