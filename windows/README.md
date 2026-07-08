# 发票 PDF 合并工具 Windows 版

这是 macOS 定稿版的 Windows/Electron 实现，面向公司同事使用。

## 功能

- 本地 PDF 导入
- QQ、网易 163、网易 126、网易 yeah.net 邮箱导入 PDF/ZIP 附件
- 账号和授权码记忆
- 12306 ZIP 自动解压并提取 PDF
- 忽略 OFD/XML 等非 PDF 合并文件
- 剔除滴滴/网约车行程单，保留机票电子客票行程单 PDF
- 导入后自动加入合并列表
- 应用内 PDF 预览
- 选中文件后按空格预览
- 合并并保存 PDF

## 开发运行

```bash
pnpm install
pnpm start
```

## 测试

```bash
pnpm test
```

## Windows 安装包

```bash
pnpm build:win
```

生成结果在 `dist/` 目录。
