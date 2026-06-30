const fs = require("fs/promises");
const path = require("path");
const yauzl = require("yauzl");
const { isTravelDocument } = require("./filters");

function sanitizeFilename(filename) {
  return String(filename || "attachment")
    .replace(/[\\/:*?"<>|]/g, "_")
    .trim();
}

async function uniquePath(directory, filename) {
  const parsed = path.parse(sanitizeFilename(filename));
  let candidate = path.join(directory, `${parsed.name}${parsed.ext}`);
  let index = 1;

  while (true) {
    try {
      await fs.access(candidate);
      candidate = path.join(directory, `${parsed.name}-${index}${parsed.ext}`);
      index += 1;
    } catch {
      return candidate;
    }
  }
}

async function extractZip(zipPath, outputDirectory) {
  await fs.mkdir(outputDirectory, { recursive: true });

  return new Promise((resolve, reject) => {
    yauzl.open(zipPath, { lazyEntries: true }, (openError, zipfile) => {
      if (openError) {
        reject(openError);
        return;
      }

      zipfile.readEntry();
      zipfile.on("entry", (entry) => {
        const entryPath = path.join(outputDirectory, sanitizeFilename(entry.fileName));

        if (/\/$/.test(entry.fileName)) {
          fs.mkdir(entryPath, { recursive: true })
            .then(() => zipfile.readEntry())
            .catch(reject);
          return;
        }

        zipfile.openReadStream(entry, async (streamError, readStream) => {
          if (streamError) {
            reject(streamError);
            return;
          }

          try {
            await fs.mkdir(path.dirname(entryPath), { recursive: true });
            const chunks = [];
            readStream.on("data", (chunk) => chunks.push(chunk));
            readStream.on("end", async () => {
              await fs.writeFile(entryPath, Buffer.concat(chunks));
              zipfile.readEntry();
            });
            readStream.on("error", reject);
          } catch (error) {
            reject(error);
          }
        });
      });
      zipfile.on("end", resolve);
      zipfile.on("error", reject);
    });
  });
}

async function listPdfs(directory) {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  const result = [];

  for (const entry of entries) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      result.push(...await listPdfs(fullPath));
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".pdf")) {
      result.push(fullPath);
    }
  }

  return result;
}

async function maybeKeepPdf(pdfPath, destinationDirectory, counters, skipTravelPDF) {
  const filename = path.basename(pdfPath);

  if (skipTravelPDF && isTravelDocument(filename)) {
    counters.skippedTravelPDFCount += 1;
    return null;
  }

  const destination = await uniquePath(destinationDirectory, filename);
  if (destination !== pdfPath) {
    await fs.copyFile(pdfPath, destination);
  }
  return destination;
}

async function processAttachments(attachments, downloadDirectory, { skipTravelPDF = true } = {}) {
  await fs.mkdir(downloadDirectory, { recursive: true });

  const pdfPaths = [];
  const counters = {
    skippedTravelPDFCount: 0,
    extractedZipCount: 0
  };

  for (const attachment of attachments) {
    const filename = sanitizeFilename(attachment.filename);
    const lowerName = filename.toLowerCase();
    const content = Buffer.isBuffer(attachment.content) ? attachment.content : Buffer.from(attachment.content || []);

    if (lowerName.endsWith(".pdf")) {
      const pdfPath = await uniquePath(downloadDirectory, filename);
      await fs.writeFile(pdfPath, content);
      if (skipTravelPDF && isTravelDocument(path.basename(pdfPath))) {
        counters.skippedTravelPDFCount += 1;
        await fs.rm(pdfPath, { force: true });
      } else {
        pdfPaths.push(pdfPath);
      }
    } else if (lowerName.endsWith(".zip")) {
      const zipPath = await uniquePath(downloadDirectory, filename);
      await fs.writeFile(zipPath, content);
      const extractDirectory = path.join(downloadDirectory, path.parse(zipPath).name);
      await extractZip(zipPath, extractDirectory);
      counters.extractedZipCount += 1;

      const extractedPdfs = await listPdfs(extractDirectory);
      for (const pdfPath of extractedPdfs) {
        const keptPath = await maybeKeepPdf(pdfPath, downloadDirectory, counters, skipTravelPDF);
        if (keptPath) {
          pdfPaths.push(keptPath);
        }
      }
    }
  }

  return {
    pdfPaths,
    ...counters,
    downloadDirectory
  };
}

module.exports = {
  processAttachments,
  sanitizeFilename,
  uniquePath,
  extractZip,
  listPdfs
};
