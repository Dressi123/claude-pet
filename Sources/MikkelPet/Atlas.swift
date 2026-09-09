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
    /// True when the atlas carries the extra sleep row past the contract's 11.
    let hasSleepRow: Bool
    /// How many rows this sheet actually carries. Rows past the eleventh are
    /// this app's own additions and each is optional.
    let rowCount: Int

    var cellSize: CGSize {
        CGSize(width: AtlasGeometry.cellWidth, height: AtlasGeometry.cellHeight)
    }

    /// Where the artwork actually is. Inside the .app it is in the usual
    /// `Contents/Resources`, which is the only place an app bundle can seal it
    /// under a signature. `Bundle.module` is the fallback, for running the bare
    /// SwiftPM binary during development.
    ///
    /// `Bundle.module` alone is not enough, and relying on it was expensive:
    /// its generated accessor looks beside the executable and then falls back
    /// to an absolute path inside `.build`. In an .app neither is right, so the
    /// installed app was quietly reading its spritesheet out of the build
    /// directory of whatever checkout built it. That made the app break if the
    /// checkout moved and made macOS ask, at every launch, for access to the
    /// folder the repository happened to sit in.
    private static func resourceURL(_ name: String, extension ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }

    init() throws {
        guard
            let manifestURL = Self.resourceURL("pet", extension: "json"),
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
            let sheetURL = Self.resourceURL(spriteName, extension: spriteExt),
            let source = CGImageSourceCreateWithURL(sheetURL as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AtlasError.missingResource(manifest.spritesheetPath)
        }

        // Eleven rows is the floor, since that is what every state and look
        // direction needs. Anything above it is this app's own: sleep, then the
        // look blinks. Rows are counted rather than matched against a fixed
        // height, so adding one is an edit to `AtlasGeometry` and nothing else.
        let expectedWidth = AtlasGeometry.columns * AtlasGeometry.cellWidth
        guard image.width == expectedWidth,
              image.height % AtlasGeometry.cellHeight == 0,
              image.height / AtlasGeometry.cellHeight >= AtlasGeometry.contractRows
        else {
            throw AtlasError.wrongDimensions(width: image.width, height: image.height)
        }
        rowCount = image.height / AtlasGeometry.cellHeight
        hasSleepRow = rowCount > SleepRow.row
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

    /// The closed-eye twin of a look direction, or nil when this sheet has no
    /// row for it. Nil means that direction simply does not blink, which is why
    /// half a set is still worth shipping.
    /// The closed-eye twin of a pose, or nil when this sheet has no row for
    /// that state. Nil means that state does not blink.
    func blinkCell(state: PetState, frame: Int) -> CGImage? {
        guard let row = state.blinkRow, row < rowCount else { return nil }
        return cell(row: row, column: min(frame, state.frameCount - 1))
    }

    func lookBlinkCell(index: Int) -> CGImage? {
        let cell = AtlasGeometry.lookBlinkCell(index: index)
        guard cell.row < rowCount else { return nil }
        return self.cell(row: cell.row, column: cell.column)
    }

    /// A frame of the sleep row, or the still fallback when the atlas has none.
    func sleepCell(column: Int) -> CGImage? {
        guard hasSleepRow else {
            return cell(row: AtlasGeometry.sleepingCell.row,
                        column: AtlasGeometry.sleepingCell.column)
        }
        return cell(row: SleepRow.row, column: column)
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
                return "Spritesheet is \(width)x\(height); expected \(AtlasGeometry.columns * AtlasGeometry.cellWidth) wide and a whole number of \(AtlasGeometry.cellHeight)px rows, at least \(AtlasGeometry.contractRows)."
            }
        }
    }
}
