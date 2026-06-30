const path = require("path");
const { ImapFlow } = require("imapflow");
const { simpleParser } = require("mailparser");
const { processAttachments } = require("./attachments");

function timestamp() {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, "0");
  return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
}

async function importRecentInvoices({ emailAddress, authCode, daysBack, skipTravelPDF, downloadsDirectory, onProgress }) {
  const client = new ImapFlow({
    host: "imap.qq.com",
    port: 993,
    secure: true,
    auth: {
      user: emailAddress,
      pass: authCode
    },
    logger: false
  });

  const since = new Date(Date.now() - Number(daysBack || 3) * 24 * 60 * 60 * 1000);
  const downloadDirectory = path.join(downloadsDirectory, "发票PDF合并", `邮箱导入-${timestamp()}`);
  const attachments = [];

  onProgress?.("正在连接 imap.qq.com...");
  await client.connect();

  let lock;
  try {
    onProgress?.("正在读取收件箱...");
    lock = await client.getMailboxLock("INBOX");

    const uids = await client.search({ since });
    let index = 0;

    for await (const message of client.fetch(uids, { source: true, uid: true })) {
      index += 1;
      onProgress?.(`正在读取邮件附件 ${index}/${uids.length}...`);
      const parsed = await simpleParser(message.source);

      for (const attachment of parsed.attachments || []) {
        const filename = attachment.filename || "";
        const lower = filename.toLowerCase();
        if (lower.endsWith(".pdf") || lower.endsWith(".zip")) {
          attachments.push({
            filename,
            content: attachment.content
          });
        }
      }
    }
  } finally {
    lock?.release();
    await client.logout().catch(() => {});
  }

  onProgress?.("正在处理 PDF 和压缩包...");
  return processAttachments(attachments, downloadDirectory, { skipTravelPDF });
}

module.exports = {
  importRecentInvoices
};
