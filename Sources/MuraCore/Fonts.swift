import CoreText
import CryptoKit
import Foundation

/// Excalidraw's handwriting fonts. They are downloaded once by `mura setup` instead of living in the repo.
struct FontAsset {
    let file: String
    let postScriptName: String
    let url: String
    let sha256: String
    let license: String

    static let all = [
        FontAsset(file: "Virgil.woff2", postScriptName: "Virgil3YOFF",
                  url: "https://raw.githubusercontent.com/excalidraw/virgil/main/Virgil.woff2",
                  sha256: "9976295bfe709bdea64839a4d4e9a1d436dd6eb67538399a5a0e8b8fadbcf1cf",
                  license: "OFL-1.1, Excalidraw"),
        FontAsset(file: "Xiaolai-Regular.ttf", postScriptName: "Xiaolai",
                  url: "https://github.com/lxgw/kose-font/releases/download/v3.126/Xiaolai-Regular.ttf",
                  sha256: "e2f68daf0e72777a8cf58bc83de1b98634b251e537ddbfca24b0ae50d1802da2",
                  license: "OFL-1.1, LXGW"),
    ]
}

struct Fonts {
    let home: Home
    private static var registered: Set<String> = []

    func path(_ asset: FontAsset) -> URL { home.fonts.appendingPathComponent(asset.file) }
    func installed(_ asset: FontAsset) -> Bool { FileManager.default.fileExists(atPath: path(asset).path) }
    var missing: [FontAsset] { FontAsset.all.filter { !installed($0) } }

    func install() throws -> [String] {
        try home.ensure()
        var fetched: [String] = []
        for asset in missing {
            guard let url = URL(string: asset.url) else { continue }
            let data: Data
            do { data = try Data(contentsOf: url) } catch {
                throw MuraError.failed("Download failed for \(asset.file): \(error.localizedDescription)", code: "network")
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == asset.sha256 else {
                throw MuraError.failed("Checksum mismatch for \(asset.file) (got \(digest))", code: "checksum")
            }
            try data.write(to: path(asset), options: .atomic)
            fetched.append(asset.file)
        }
        return fetched
    }

    /// Handwriting font at `size`: Virgil for Latin, Xiaolai for CJK, system fonts as a last resort.
    func font(size: CGFloat) -> CTFont {
        var names: [String] = []
        for asset in FontAsset.all where installed(asset) {
            if !Fonts.registered.contains(path(asset).path) {
                CTFontManagerRegisterFontsForURL(path(asset) as CFURL, .process, nil)
                Fonts.registered.insert(path(asset).path)
            }
            names.append(asset.postScriptName)
        }
        names += ["PingFangSC-Regular", "Helvetica"]
        let cascade = names.dropFirst().map { CTFontDescriptorCreateWithNameAndSize($0 as CFString, size) }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: names[0],
            kCTFontCascadeListAttribute: cascade,
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}
