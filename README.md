# 发票 PDF 合并工具

一个面向个人和团队报销场景的本地桌面工具，用来把分散在本地文件夹和邮箱里的 PDF 发票快速整理、预览并合并成一个 PDF。

项目包含两个版本：

- `macos/`：SwiftUI + PDFKit 原生 macOS 版本
- `windows/`：Electron Windows 版本

## 业务场景

- 差旅报销：高铁、机票、酒店、网约车等发票需要统一提交。
- 邮箱收票：发票来自 QQ、网易等邮箱附件，需要按时间范围批量下载。
- 12306 发票：邮件附件通常是 ZIP 压缩包，需要自动解压并提取 PDF。
- 网约车报销：滴滴等邮件中常同时包含发票和行程单，需要保留发票、剔除行程单。
- 多人协作：财务或行政同事希望用统一工具完成发票整理，减少手工下载、打开、复制、合并。

## 功能说明

- 多个 PDF 本地导入，支持拖拽。
- 从 QQ、网易 163、网易 126、网易 yeah.net 邮箱导入近 N 日 PDF/ZIP 附件。
- 自动解压 12306 ZIP 发票附件。
- 自动忽略 OFD、XML 等不能参与 PDF 合并的附件。
- 自动剔除滴滴、网约车等行程单类 PDF。
- 保留机票电子客票行程单等可作为报销凭证的 PDF。
- 邮箱导入成功后，PDF 自动加入合并列表。
- 支持列表内 PDF 预览，不调用外部 WPS 或系统默认应用。
- 支持选中文件后按空格预览。
- 支持调整顺序、删除、清空。
- 一键合并并保存为本地 PDF。
- 账号和邮箱授权码可按邮箱类型本机记忆。

## 隐私与安全

- 所有 PDF 处理都在本机完成，不上传到任何服务器。
- 邮箱登录使用“邮箱授权码 / 客户端授权码”，不是邮箱登录密码。
- macOS 版本将账号信息保存到 Keychain。
- Windows 版本使用 Electron 本机安全存储能力保存账号信息。
- 开源仓库不包含个人邮箱、授权码、构建产物和本机临时文件。

## 目录结构

```text
.
├── macos/      # macOS 原生版本
├── windows/    # Windows Electron 版本
├── LICENSE
└── README.md
```

## macOS 开发与打包

进入 `macos/`：

```bash
swift run
```

打包 DMG：

```bash
bash scripts/build_dmg.sh
```

生成文件在 `macos/dist/`，该目录不会提交到 Git。

## Windows 开发与打包

进入 `windows/`：

```bash
pnpm install
pnpm start
```

运行测试：

```bash
pnpm test
```

打包 Windows 安装包：

```bash
pnpm build:win
```

生成文件在 `windows/dist/`，该目录不会提交到 Git。

## 已验证内容

- macOS 版本可构建并生成 DMG。
- Windows 版本核心逻辑测试通过。
- Windows 安装包可在 macOS 环境下完成构建并通过基础文件校验。

说明：真实 Windows 安装和运行仍建议在 Windows 电脑或虚拟机中再做一次人工验收。

## 适用边界

本工具聚焦“发票 PDF 收集、筛选、预览、合并”。它不做发票真伪校验、税务合规判断、OCR 金额识别或企业报销系统审批流。

## License

MIT
