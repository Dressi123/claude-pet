// Loads the packaged spritesheet and hands out per-cell images.

import PetCore
import AppKit
import ImageIO

struct PetManifest: Decodable {
    let id: String
    let displayName: String
    let description: String
    let spriteVersionNumber: Int
    let spritesheetPath: String
}

final class Atlas {
    let manifest: PetManifest
    private let sheet: CGImage
    private var cellCache: [Int: CGImage] = [:]

    var cellSize: CGSize {
        CGSize(width: AtlasGeometry.cellWidth, height: AtlasGeometry.cellHeight)
    }

    init() throws {
        let bundle = Bundle.module
        guard
            let manifestURL = bundle.url(forResource: "pet", withExtension: "json", subdirectory: "Resources"),
            let manifestData = try? Data(contentsOf: manifestURL)
        else {
            throw AtlasError.missingResource("pet.json")
        }
        manifest = try JSONDecoder().decode(PetManifest.self, from: manifestData)

        guard manifest.spriteVersionNumber == 2 else {
            throw AtlasError.unsupportedVersion(manifest.spriteVersionNumber)
        }

        let spriteName = (manifest.spritesheetPath as NSString).deletingPathExtension
        let spriteExt = (manifest.spritesheetPath as NSString).pathExtension
        guard
            let sheetURL = bundle.url(forResource: spriteName, withExtension: spriteExt, subdirectory: "Resources"),
            let source = CGImageSourceCreateWithURL(sheetURL as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AtlasError.missingResource(manifest.spritesheetPath)
        }

        let expectedWidth = AtlasGeometry.columns * AtlasGeometry.cellWidth
        let expectedHeight = AtlasGeometry.rows * AtlasGeometry.cellHeight
        guard image.width == expectedWidth, image.height == expectedHeight else {
            throw AtlasError.wrongDimensions(width: image.width, height: image.height)
        }
        sheet = image
    }

    /// Cells are cropped views onto the decoded sheet, so this is cheap and the
    /// 88 possible crops are cached on first use.
    func cell(row: Int, column: Int) -> CGImage? {
        let key = row * AtlasGeometry.columns + column
        if let cached = cellCache[key] { return cached }
        let rect = CGRect(
            x: column * AtlasGeometry.cellWidth,
            y: row * AtlasGeometry.cellHeight,
            width: AtlasGeometry.cellWidth,
            height: AtlasGeometry.cellHeight
        )
        guard let cropped = sheet.cropping(to: rect) else { return nil }
        cellCache[key] = cropped
        return cropped
    }

    func cell(state: PetState, frame: Int) -> CGImage? {
        cell(row: state.row, column: min(frame, state.frameCount - 1))
    }

    func lookCell(index: Int) -> CGImage? {
        let cell = AtlasGeometry.lookCell(index: index)
        return self.cell(row: cell.row, column: cell.column)
    }

    var neutralCell: CGImage? {
        cell(row: AtlasGeometry.neutralCell.row, column: AtlasGeometry.neutralCell.column)
    }

    enum AtlasError: LocalizedError {
        case missingResource(String)
        case unsupportedVersion(Int)
        case wrongDimensions(width: Int, height: Int)

        var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                return "Could not load bundled resource \(name)."
            case .unsupportedVersion(let version):
                return "Pet declares spriteVersionNumber \(version); this app needs 2."
            case .wrongDimensions(let width, let height):
                return "Spritesheet is \(width)x\(height); the v2 contract requires 1536x2288."
            }
        }
    }
}
