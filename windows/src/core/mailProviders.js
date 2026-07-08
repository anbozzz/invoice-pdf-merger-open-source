const MAIL_PROVIDERS = {
  qq: {
    id: "qq",
    name: "QQ 邮箱",
    host: "imap.qq.com"
  },
  netease163: {
    id: "netease163",
    name: "网易 163 邮箱",
    host: "imap.163.com"
  },
  netease126: {
    id: "netease126",
    name: "网易 126 邮箱",
    host: "imap.126.com"
  },
  neteaseYeah: {
    id: "neteaseYeah",
    name: "网易 yeah.net 邮箱",
    host: "imap.yeah.net"
  }
};

function providerFor(providerId) {
  return MAIL_PROVIDERS[providerId] || MAIL_PROVIDERS.qq;
}

module.exports = {
  MAIL_PROVIDERS,
  providerFor
};
