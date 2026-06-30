const state = {
  files: [],
  selectedId: null,
  unsubscribeProgress: null
};

const elements = {
  dropZone: document.getElementById("dropZone"),
  emptyState: document.querySelector(".empty-state"),
  fileTable: document.getElementById("fileTable"),
  fileTableBody: document.getElementById("fileTableBody"),
  summaryText: document.getElementById("summaryText"),
  mailImportButton: document.getElementById("mailImportButton"),
  localImportButton: document.getElementById("localImportButton"),
  clearButton: document.getElementById("clearButton"),
  previewButton: document.getElementById("previewButton"),
  moveUpButton: document.getElementById("moveUpButton"),
  moveDownButton: document.getElementById("moveDownButton"),
  removeButton: document.getElementById("removeButton"),
  mergeButton: document.getElementById("mergeButton"),
  mailDialog: document.getElementById("mailDialog"),
  emailInput: document.getElementById("emailInput"),
  authCodeInput: document.getElementById("authCodeInput"),
  daysInput: document.getElementById("daysInput"),
  skipTravelInput: document.getElementById("skipTravelInput"),
  mailStatus: document.getElementById("mailStatus"),
  clearCredentialButton: document.getElementById("clearCredentialButton"),
  startMailImportButton: document.getElementById("startMailImportButton"),
  previewDialog: document.getElementById("previewDialog"),
  previewTitle: document.getElementById("previewTitle"),
  previewMeta: document.getElementById("previewMeta"),
  previewFrame: document.getElementById("previewFrame"),
  closePreviewButton: document.getElementById("closePreviewButton")
};

function formatBytes(size) {
  if (!Number.isFinite(size)) {
    return "未知大小";
  }
  if (size < 1024) {
    return `${size} B`;
  }
  if (size < 1024 * 1024) {
    return `${(size / 1024).toFixed(1)} KB`;
  }
  return `${(size / 1024 / 1024).toFixed(1)} MB`;
}

function fileName(filePath) {
  return String(filePath).split(/[\\/]/).pop();
}

function newFile(info) {
  return {
    id: `${Date.now()}-${Math.random().toString(16).slice(2)}`,
    path: info.path,
    pageCount: info.pageCount,
    size: info.size
  };
}

function addFiles(infos) {
  const existingPaths = new Set(state.files.map((file) => file.path));
  const freshFiles = infos
    .filter((info) => info && info.path && !existingPaths.has(info.path))
    .map(newFile);

  state.files.push(...freshFiles);
  if (!state.selectedId && state.files.length > 0) {
    state.selectedId = state.files[0].id;
  }
  render();
}

function selectedIndex() {
  return state.files.findIndex((file) => file.id === state.selectedId);
}

function selectedFile() {
  const index = selectedIndex();
  return index >= 0 ? state.files[index] : null;
}

function render() {
  const hasFiles = state.files.length > 0;
  elements.emptyState.classList.toggle("hidden", hasFiles);
  elements.fileTable.classList.toggle("hidden", !hasFiles);
  elements.fileTableBody.innerHTML = "";

  for (const file of state.files) {
    const row = document.createElement("tr");
    row.classList.toggle("selected", file.id === state.selectedId);
    row.innerHTML = `
      <td><div class="file-name" title="${file.path}">${fileName(file.path)}</div></td>
      <td>${file.pageCount}</td>
      <td>${formatBytes(file.size)}</td>
      <td>
        <div class="row-actions">
          <button title="预览" data-action="preview">👁</button>
        </div>
      </td>
    `;
    row.addEventListener("click", () => {
      state.selectedId = file.id;
      render();
    });
    row.querySelector('[data-action="preview"]').addEventListener("click", (event) => {
      event.stopPropagation();
      state.selectedId = file.id;
      previewSelected();
    });
    elements.fileTableBody.appendChild(row);
  }

  const totalPages = state.files.reduce((sum, file) => sum + file.pageCount, 0);
  elements.summaryText.textContent = `${state.files.length} 个文件，${totalPages} 页`;

  const index = selectedIndex();
  elements.clearButton.disabled = !hasFiles;
  elements.previewButton.disabled = index < 0;
  elements.moveUpButton.disabled = index <= 0;
  elements.moveDownButton.disabled = index < 0 || index >= state.files.length - 1;
  elements.removeButton.disabled = index < 0;
  elements.mergeButton.disabled = !hasFiles;
}

async function importLocalPdfs() {
  try {
    const infos = await window.invoiceApp.selectPdfs();
    addFiles(infos);
  } catch (error) {
    alert(`导入失败：${error.message}`);
  }
}

async function importDroppedFiles(files) {
  const pdfPaths = [...files]
    .map((file) => file.path)
    .filter((filePath) => filePath && filePath.toLowerCase().endsWith(".pdf"));

  const infos = [];
  for (const filePath of pdfPaths) {
    try {
      infos.push(await window.invoiceApp.getPdfInfo(filePath));
    } catch {
      // Ignore unreadable PDFs and keep importing the rest.
    }
  }
  addFiles(infos);
}

async function openMailDialog() {
  const credentials = await window.invoiceApp.getCredentials();
  elements.emailInput.value = credentials.emailAddress || "";
  elements.authCodeInput.value = credentials.authCode || "";
  elements.daysInput.value = "3";
  elements.skipTravelInput.checked = true;
  elements.mailStatus.textContent = "默认下载近 3 日邮件中的 PDF 和 ZIP 附件。";
  elements.mailDialog.showModal();
}

async function startMailImport() {
  elements.startMailImportButton.disabled = true;
  elements.mailStatus.textContent = "正在连接 QQ 邮箱...";

  if (state.unsubscribeProgress) {
    state.unsubscribeProgress();
  }
  state.unsubscribeProgress = window.invoiceApp.onMailProgress((message) => {
    elements.mailStatus.textContent = message;
  });

  try {
    const result = await window.invoiceApp.importMail({
      emailAddress: elements.emailInput.value.trim(),
      authCode: elements.authCodeInput.value,
      daysBack: Number(elements.daysInput.value || 3),
      skipTravelPDF: elements.skipTravelInput.checked
    });

    const infos = [];
    for (const filePath of result.pdfPaths || []) {
      infos.push(await window.invoiceApp.getPdfInfo(filePath));
    }
    addFiles(infos);
    elements.mailDialog.close();
    alert(`已完成邮箱导入：\n已加入合并列表：${infos.length} 个 PDF\n跳过行程单：${result.skippedTravelPDFCount} 个\n解压压缩包：${result.extractedZipCount} 个\n\n文件位置：\n${result.downloadDirectory}`);
  } catch (error) {
    alert(`邮箱导入失败：${error.message}`);
  } finally {
    elements.startMailImportButton.disabled = false;
  }
}

async function previewSelected() {
  const file = selectedFile();
  if (!file) {
    return;
  }
  elements.previewTitle.textContent = fileName(file.path);
  elements.previewMeta.textContent = `${file.pageCount} 页 · ${formatBytes(file.size)}`;
  elements.previewFrame.src = await window.invoiceApp.fileUrl(file.path);
  elements.previewDialog.showModal();
}

function moveSelected(offset) {
  const index = selectedIndex();
  const destination = index + offset;
  if (index < 0 || destination < 0 || destination >= state.files.length) {
    return;
  }
  const [file] = state.files.splice(index, 1);
  state.files.splice(destination, 0, file);
  render();
}

function removeSelected() {
  const index = selectedIndex();
  if (index < 0) {
    return;
  }
  state.files.splice(index, 1);
  state.selectedId = state.files[index]?.id || state.files[state.files.length - 1]?.id || null;
  render();
}

async function mergeAndSave() {
  try {
    const result = await window.invoiceApp.saveMergedPdf(state.files.map((file) => file.path));
    if (result) {
      alert(`已保存到：\n${result.outputPath}`);
    }
  } catch (error) {
    alert(`保存失败：${error.message}`);
  }
}

elements.localImportButton.addEventListener("click", importLocalPdfs);
elements.mailImportButton.addEventListener("click", openMailDialog);
elements.clearButton.addEventListener("click", () => {
  state.files = [];
  state.selectedId = null;
  render();
});
elements.previewButton.addEventListener("click", previewSelected);
elements.moveUpButton.addEventListener("click", () => moveSelected(-1));
elements.moveDownButton.addEventListener("click", () => moveSelected(1));
elements.removeButton.addEventListener("click", removeSelected);
elements.mergeButton.addEventListener("click", mergeAndSave);
elements.startMailImportButton.addEventListener("click", startMailImport);
elements.clearCredentialButton.addEventListener("click", async () => {
  await window.invoiceApp.clearCredentials();
  elements.emailInput.value = "";
  elements.authCodeInput.value = "";
  elements.mailStatus.textContent = "已清除本机保存的 QQ 邮箱信息。";
});
elements.closePreviewButton.addEventListener("click", () => elements.previewDialog.close());

elements.dropZone.addEventListener("dragover", (event) => {
  event.preventDefault();
  elements.dropZone.classList.add("dragging");
});
elements.dropZone.addEventListener("dragleave", () => {
  elements.dropZone.classList.remove("dragging");
});
elements.dropZone.addEventListener("drop", async (event) => {
  event.preventDefault();
  elements.dropZone.classList.remove("dragging");
  await importDroppedFiles(event.dataTransfer.files);
});

document.addEventListener("keydown", (event) => {
  if (event.code === "Space" && !elements.previewDialog.open && !elements.mailDialog.open) {
    event.preventDefault();
    previewSelected();
  }
  if (event.key === "Escape" && elements.previewDialog.open) {
    elements.previewDialog.close();
  }
});

render();
