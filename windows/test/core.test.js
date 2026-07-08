const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const { PDFDocument, StandardFonts } = require("pdf-lib");
const { getPdfInfo, mergePdfs } = require("../src/core/pdf");
const { processAttachments } = require("../src/core/attachments");
const { isTravelDocument } = require("../src/core/filters");
const { MAIL_PROVIDERS } = require("../src/core/mailProviders");

async function makePdf(filePath, text, pageCount = 1) {
  const document = await PDFDocument.create();
  const font = await document.embedFont(StandardFonts.Helvetica);

  for (let index = 0; index < pageCount; index += 1) {
    const page = document.addPage([420, 300]);
    page.drawText(`${text} ${index + 1}`, {
      x: 40,
      y: 240,
      size: 18,
      font
    });
  }

  await fs.writeFile(filePath, await document.save());
}

async function run() {
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "invoice-pdf-merger-test-"));
  const firstPdf = path.join(tempRoot, "发票A.pdf");
  const secondPdf = path.join(tempRoot, "发票B.pdf");
  const mergedPdf = path.join(tempRoot, "合并.pdf");
  const downloadDirectory = path.join(tempRoot, "downloads");

  await makePdf(firstPdf, "invoice-a", 1);
  await makePdf(secondPdf, "invoice-b", 2);

  const firstInfo = await getPdfInfo(firstPdf);
  const secondInfo = await getPdfInfo(secondPdf);
  assert.strictEqual(firstInfo.pageCount, 1);
  assert.strictEqual(secondInfo.pageCount, 2);

  await mergePdfs([firstPdf, secondPdf], mergedPdf);
  const mergedInfo = await getPdfInfo(mergedPdf);
  assert.strictEqual(mergedInfo.pageCount, 3);

  assert.strictEqual(isTravelDocument("滴滴出行行程报销单A.pdf"), true);
  assert.strictEqual(isTravelDocument("订单1128148843091564-电子普通发票(1).pdf"), false);
  assert.strictEqual(isTravelDocument("航空运输电子客票行程单.pdf"), false);
  assert.strictEqual(MAIL_PROVIDERS.qq.host, "imap.qq.com");
  assert.strictEqual(MAIL_PROVIDERS.netease163.host, "imap.163.com");
  assert.strictEqual(MAIL_PROVIDERS.netease126.host, "imap.126.com");
  assert.strictEqual(MAIL_PROVIDERS.neteaseYeah.host, "imap.yeah.net");

  const firstBytes = await fs.readFile(firstPdf);
  const secondBytes = await fs.readFile(secondPdf);
  const result = await processAttachments(
    [
      { filename: "滴滴出行行程报销单A.pdf", content: firstBytes },
      { filename: "航空运输电子客票行程单.pdf", content: secondBytes }
    ],
    downloadDirectory,
    { skipTravelPDF: true }
  );

  assert.strictEqual(result.skippedTravelPDFCount, 1);
  assert.strictEqual(result.pdfPaths.length, 1);
  assert.strictEqual(path.basename(result.pdfPaths[0]), "航空运输电子客票行程单.pdf");

  await fs.rm(tempRoot, { recursive: true, force: true });
  console.log("core tests passed");
}

run().catch((error) => {
  console.error(error);
  process.exit(1);
});
