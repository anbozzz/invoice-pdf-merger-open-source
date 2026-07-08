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

function credentialPrefix(providerId) {
  return `mail.${providerId || "qq"}`;
}

ipcMain.handle("credentials:get", (_event, providerId = store.get("mail.selectedProvider", "qq")) => {
  const prefix = credentialPrefix(providerId);
  return {
    providerId,
    emailAddress: store.get(`${prefix}.emailAddress`, ""),
    authCode: decryptedValue(store.get(`${prefix}.authCode`, ""))
  };
});

ipcMain.handle("credentials:save", (_event, credentials) => {
  const providerId = credentials.providerId || "qq";
  const prefix = credentialPrefix(providerId);
  store.set("mail.selectedProvider", providerId);
  store.set(`${prefix}.emailAddress`, credentials.emailAddress || "");
  store.set(`${prefix}.authCode`, encryptedValue(credentials.authCode || ""));
  return true;
});

ipcMain.handle("credentials:clear", (_event, providerId = store.get("mail.selectedProvider", "qq")) => {
  const prefix = credentialPrefix(providerId);
  store.delete(`${prefix}.emailAddress`);
  store.delete(`${prefix}.authCode`);
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
  const providerId = request.providerId || "qq";
  const prefix = credentialPrefix(providerId);
  const credentials = {
    providerId,
    emailAddress: request.emailAddress || "",
    authCode: request.authCode || ""
  };
  store.set("mail.selectedProvider", providerId);
  store.set(`${prefix}.emailAddress`, credentials.emailAddress);
  store.set(`${prefix}.authCode`, encryptedValue(credentials.authCode));

  return importRecentInvoices({
    ...request,
    providerId,
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
