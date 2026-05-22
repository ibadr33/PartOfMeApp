// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PartOfMeApp",
    platforms: [
        .iOS(.v16) // تحديد منصة الآيفون iOS 16 فما فوق
    ],
    products: [
        .executable(name: "PartOfMeApp", targets: ["PartOfMeApp"])
    ],
    targets: [
        .executableTarget(
            name: "PartOfMeApp",
            path: "Sources"
        )
    ]
)
