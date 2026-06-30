function containsAny(text, keywords) {
  const normalized = String(text || "").toLowerCase();
  return keywords.some((keyword) => normalized.includes(String(keyword).toLowerCase()));
}

function isTravelDocument(filename, text = "") {
  const combinedText = `${filename || ""}\n${text || ""}`.toLowerCase();

  const flightInvoiceKeywords = [
    "航空运输电子客票行程单",
    "电子客票行程单",
    "航空电子客票",
    "航空公司",
    "航班",
    "机票",
    "客票",
    "民航"
  ];

  if (containsAny(combinedText, flightInvoiceKeywords)) {
    return false;
  }

  const rideHailingKeywords = [
    "滴滴",
    "曹操",
    "网约车",
    "t3出行",
    "高德打车",
    "首汽约车",
    "出行行程报销单",
    "出租车"
  ];
  const travelKeywords = ["行程单", "行程报销单", "行程明细", "行程详单", "itinerary", "trip"];

  return containsAny(combinedText, rideHailingKeywords) && containsAny(combinedText, travelKeywords);
}

module.exports = {
  containsAny,
  isTravelDocument
};
