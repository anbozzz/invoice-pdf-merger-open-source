const fs = require("fs/promises");
const { PDFDocument } = require("pdf-lib");

async function getPdfInfo(filePath) {
  const bytes = await fs.readFile(filePath);
  const document = await PDFDocument.load(bytes, { ignoreEncryption: true });
  return {
    path: filePath,
    pageCount: document.getPageCount(),
    size: bytes.length
  };
}

async function mergePdfs(inputPaths, outputPath) {
  const merged = await PDFDocument.create();

  for (const inputPath of inputPaths) {
    const bytes = await fs.readFile(inputPath);
    const source = await PDFDocument.load(bytes, { ignoreEncryption: true });
    const copiedPages = await merged.copyPages(source, source.getPageIndices());
    copiedPages.forEach((page) => merged.addPage(page));
  }

  const mergedBytes = await merged.save();
  await fs.writeFile(outputPath, mergedBytes);
  return {
    outputPath,
    bytes: mergedBytes.length
  };
}

module.exports = {
  getPdfInfo,
  mergePdfs
};
