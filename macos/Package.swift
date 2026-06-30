// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "InvoicePDFMerger",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "InvoicePDFMerger",
            targets: ["InvoicePDFMerger"]
        )
    ],
    targets: [
        .executableTarget(
            name: "InvoicePDFMerger"
        )
    ]
)
