const { app, BrowserWindow, dialog, ipcMain, safeStorage } = require("electron");
const Store = require("electron-store");
const fs = require("fs/promises");
const path = require("path");
const { pathToFileURL } = require("url");
const { getPdfInfo, mergePdfs } = require("../core/pdf");
const { importRecentInvoices } = require("../core/mail");

const store = new Store({
  name: "settings"
});

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 980,
    height: 700,
    minWidth: 820,
    minHeight: 560,
    title: "发票PDF合并",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, "../renderer/index.html"));
}

app.whenReady().then(createWindow);

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});

function encryptedValue(value) {
  if (!value) {
    return "";
  }
  if (safeStorage.isEncryptionAvailable()) {
    return safeStorage.encryptString(value).toString("base64");
  }
  return Buffer.from(value, "utf8").toString("base64");
}

function decryptedValue(value) {
  if (!value) {
    return "";
  }
  const buffer = Buffer.from(value, "base64");
  if (safeStorage.isEncryptionAvailable()) {
    return safeStorage.decryptString(buffer);
  }
  return buffer.toString("utf8");
}

ipcMain.handle("credentials:get", () => ({
  emailAddress: store.get("qq.emailAddress", ""),
  authCode: decryptedValue(store.get("qq.authCode", ""))
}));

ipcMain.handle("credentials:save", (_event, credentials) => {
  store.set("qq.emailAddress", credentials.emailAddress || "");
  store.set("qq.authCode", encryptedValue(credentials.authCode || ""));
  return true;
});

ipcMain.handle("credentials:clear", () => {
  store.delete("qq.emailAddress");
  store.delete("qq.authCode");
  return true;
});

ipcMain.handle("dialog:selectPdfs", async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: "导入 PDF",
    properties: ["openFile", "multiSelections"],
    filters: [{ name: "PDF 文件", extensions: ["pdf"] }]
  });

  if (result.canceled) {
    return [];
  }

  return Promise.all(result.filePaths.map(getPdfInfo));
});

ipcMain.handle("dialog:saveMergedPdf", async (_event, inputPaths) => {
  const result = await dialog.showSaveDialog(mainWindow, {
    title: "保存合并后的 PDF",
    defaultPath: `发票合并_${new Date().toISOString().slice(0, 10)}.pdf`,
    filters: [{ name: "PDF 文件", extensions: ["pdf"] }]
  });

  if (result.canceled || !result.filePath) {
    return null;
  }

  return mergePdfs(inputPaths, result.filePath);
});

ipcMain.handle("pdf:info", async (_event, filePath) => getPdfInfo(filePath));

ipcMain.handle("pdf:fileUrl", (_event, filePath) => pathToFileURL(filePath).toString());

ipcMain.handle("mail:import", async (_event, request) => {
  const credentials = {
    emailAddress: request.emailAddress || "",
    authCode: request.authCode || ""
  };
  store.set("qq.emailAddress", credentials.emailAddress);
  store.set("qq.authCode", encryptedValue(credentials.authCode));

  return importRecentInvoices({
    ...request,
    downloadsDirectory: app.getPath("downloads"),
    onProgress: (message) => {
      mainWindow?.webContents.send("mail:progress", message);
    }
  });
});

ipcMain.handle("file:stat", async (_event, filePath) => {
  const stat = await fs.stat(filePath);
  return {
    size: stat.size
  };
});
