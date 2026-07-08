const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("invoiceApp", {
  getCredentials: (providerId) => ipcRenderer.invoke("credentials:get", providerId),
  saveCredentials: (credentials) => ipcRenderer.invoke("credentials:save", credentials),
  clearCredentials: (providerId) => ipcRenderer.invoke("credentials:clear", providerId),
  selectPdfs: () => ipcRenderer.invoke("dialog:selectPdfs"),
  saveMergedPdf: (inputPaths) => ipcRenderer.invoke("dialog:saveMergedPdf", inputPaths),
  getPdfInfo: (filePath) => ipcRenderer.invoke("pdf:info", filePath),
  fileUrl: (filePath) => ipcRenderer.invoke("pdf:fileUrl", filePath),
  importMail: (request) => ipcRenderer.invoke("mail:import", request),
  onMailProgress: (callback) => {
    const listener = (_event, message) => callback(message);
    ipcRenderer.on("mail:progress", listener);
    return () => ipcRenderer.removeListener("mail:progress", listener);
  }
});
