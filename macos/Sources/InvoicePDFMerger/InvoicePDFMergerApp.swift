import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit

struct PDFFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let pageCount: Int
    let fileSizeText: String

    var name: String {
        url.lastPathComponent
    }
}

@main
struct InvoicePDFMergerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 460)
        }
        .windowStyle(.titleBar)
    }
}

struct ContentView: View {
    @State private var files: [PDFFile] = []
    @State private var selectedFileID: PDFFile.ID?
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var isTargeted = false
    @State private var showingMailImport = false
    @State private var isImportingFromMail = false
    @State private var previewFile: PDFFile?

    var selectedIndex: Int? {
        guard let selectedFileID else { return nil }
        return files.firstIndex { $0.id == selectedFileID }
    }

    var totalPages: Int {
        files.reduce(0) { $0 + $1.pageCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            fileList
            Divider()
            footer
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop(providers:))
        .alert("提示", isPresented: $showingAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showingMailImport) {
            QQMailImportSheet(
                isImporting: $isImportingFromMail,
                onImported: { result in
                    addFiles(from: result.pdfURLs)
                    showAlert(
                        """
                        已完成邮箱导入：
                        已加入合并列表：\(result.pdfURLs.count) 个 PDF
                        跳过行程单：\(result.skippedTravelPDFCount) 个
                        解压压缩包：\(result.extractedZipCount) 个

                        文件位置：
                        \(result.downloadDirectory.path)
                        """
                    )
                },
                onError: { message in
                    showAlert(message)
                }
            )
        }
        .sheet(item: $previewFile) { file in
            PDFPreviewSheet(file: file)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("发票 PDF 合并")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("导入多张 PDF 后，按列表顺序合并为一个文件。")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingMailImport = true
            } label: {
                Label("邮箱导入", systemImage: "envelope.badge")
            }
            .disabled(isImportingFromMail)

            Button {
                importPDFs()
            } label: {
                Label("导入 PDF", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button {
                clearFiles()
            } label: {
                Label("清空", systemImage: "trash")
            }
            .disabled(files.isEmpty)
        }
        .padding(20)
    }

    private var fileList: some View {
        ZStack {
            if files.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(isTargeted ? .blue : .secondary)
                    Text(isTargeted ? "松开即可导入 PDF" : "点击导入，或把 PDF 文件拖到这里")
                        .font(.headline)
                    Text("文件仅在本机处理，不会上传。")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedFileID) {
                    ForEach(files) { file in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.richtext")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.name)
                                    .lineLimit(1)
                                Text("\(file.pageCount) 页 · \(file.fileSizeText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                preview(file)
                            } label: {
                                Label("预览", systemImage: "eye")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .help("预览 PDF")
                        }
                        .tag(file.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(files.count) 个文件，\(totalPages) 页")
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                previewSelected()
            } label: {
                Label("预览", systemImage: "eye")
            }
            .disabled(selectedIndex == nil)
            .keyboardShortcut(.space, modifiers: [])
            .help("按空格键预览选中的 PDF")

            Button {
                moveSelected(offset: -1)
            } label: {
                Label("上移", systemImage: "arrow.up")
            }
            .disabled(!canMoveSelected(offset: -1))

            Button {
                moveSelected(offset: 1)
            } label: {
                Label("下移", systemImage: "arrow.down")
            }
            .disabled(!canMoveSelected(offset: 1))

            Button {
                removeSelected()
            } label: {
                Label("删除", systemImage: "minus")
            }
            .disabled(selectedIndex == nil)

            Button {
                mergeAndSave()
            } label: {
                Label("合并并保存", systemImage: "square.and.arrow.down")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .disabled(files.isEmpty)
            .keyboardShortcut("s", modifiers: [.command])
        }
        .padding(16)
    }

    private func importPDFs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            addFiles(from: panel.urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didAccept = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            didAccept = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard
                    let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    return
                }

                DispatchQueue.main.async {
                    addFiles(from: [url])
                }
            }
        }

        return didAccept
    }

    private func addFiles(from urls: [URL]) {
        var failedNames: [String] = []
        var newFiles: [PDFFile] = []

        for url in urls {
            guard url.pathExtension.lowercased() == "pdf" else {
                failedNames.append(url.lastPathComponent)
                continue
            }

            guard files.contains(where: { $0.url == url }) == false,
                  newFiles.contains(where: { $0.url == url }) == false
            else {
                continue
            }

            guard let document = PDFDocument(url: url) else {
                failedNames.append(url.lastPathComponent)
                continue
            }

            newFiles.append(
                PDFFile(
                    url: url,
                    pageCount: document.pageCount,
                    fileSizeText: fileSizeText(for: url)
                )
            )
        }

        files.append(contentsOf: newFiles)

        if selectedFileID == nil {
            selectedFileID = files.first?.id
        }

        if failedNames.isEmpty == false {
            showAlert("以下文件无法导入：\n\(failedNames.joined(separator: "\n"))")
        }
    }

    private func mergeAndSave() {
        let mergedDocument = PDFDocument()
        var insertIndex = 0

        for file in files {
            guard let document = PDFDocument(url: file.url) else {
                showAlert("无法读取：\(file.name)")
                return
            }

            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else {
                    showAlert("读取页面失败：\(file.name) 第 \(pageIndex + 1) 页")
                    return
                }

                mergedDocument.insert(page, at: insertIndex)
                insertIndex += 1
            }
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultOutputName()

        guard panel.runModal() == .OK, let outputURL = panel.url else {
            return
        }

        if mergedDocument.write(to: outputURL) {
            showAlert("已保存到：\n\(outputURL.path)")
        } else {
            showAlert("保存失败，请确认目标位置可写。")
        }
    }

    private func clearFiles() {
        files.removeAll()
        selectedFileID = nil
    }

    private func removeSelected() {
        guard let selectedIndex else { return }
        files.remove(at: selectedIndex)
        selectedFileID = files.indices.contains(selectedIndex)
            ? files[selectedIndex].id
            : files.last?.id
    }

    private func previewSelected() {
        guard let selectedIndex else { return }
        preview(files[selectedIndex])
    }

    private func preview(_ file: PDFFile) {
        previewFile = file
    }

    private func moveSelected(offset: Int) {
        guard let selectedIndex else { return }
        let destination = selectedIndex + offset
        guard files.indices.contains(destination) else { return }
        files.swapAt(selectedIndex, destination)
    }

    private func canMoveSelected(offset: Int) -> Bool {
        guard let selectedIndex else { return false }
        return files.indices.contains(selectedIndex + offset)
    }

    private func fileSizeText(for url: URL) -> String {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = values.fileSize
        else {
            return "未知大小"
        }

        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    private func defaultOutputName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "发票合并_\(formatter.string(from: Date())).pdf"
    }

    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

struct PDFPreviewSheet: View {
    let file: PDFFile

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(file.pageCount) 页 · \(file.fileSizeText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Label("关闭", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .keyboardShortcut(.cancelAction)
                .help("关闭预览")
            }
            .padding(14)

            Divider()

            PDFPreviewView(url: file.url)
                .frame(minWidth: 820, minHeight: 640)
        }
    }
}

struct PDFPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .windowBackgroundColor
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
        nsView.autoScales = true
    }
}
