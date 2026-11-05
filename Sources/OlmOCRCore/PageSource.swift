// Declaration: Code generated using Anthropic Claude (Opus 5.5)
import CoreImage
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public let targetLongestSide: CGFloat = 1288

public enum PageSourceError: LocalizedError {
    case unreadable(URL)
    case encrypted(URL)
    case noPages(URL)
    case unsupported(URL)
    case pageOutOfRange(Int)
    case renderFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): return "Could not open \(url.lastPathComponent). The file may be damaged."
        case .encrypted(let url): return "\(url.lastPathComponent) is password-protected."
        case .noPages(let url):
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            return isFolder
                ? "\(url.lastPathComponent) has no images or PDFs in it."
                : "\(url.lastPathComponent) has no pages."
        case .unsupported(let url): return "\(url.lastPathComponent) is not a PDF or an image file."
        case .pageOutOfRange(let page): return "Page \(page) does not exist."
        case .renderFailed(let page): return "Page \(page) could not be rendered."
        }
    }
}

public enum SourceKind: String, Codable, Sendable {
    case pdf
    case image
    case folder
}

public final class PageSource: @unchecked Sendable {
    public let url: URL
    public let kind: SourceKind
    public let pageCount: Int
    private let pdf: PDFDocument?
    private let imageSource: CGImageSource?
    public let imageFiles: [URL]

    public static let supportedExtensions: Set<String> = [
        "pdf", "png", "jpg", "jpeg", "tif", "tiff", "jp2", "j2k", "jpf", "heic", "heif", "gif", "bmp", "webp",
    ]

    public init(url: URL, password: String? = nil) throws {
        self.url = url
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            let files = PageSource.imageFiles(in: url)
            guard !files.isEmpty else {
                throw PageSourceError.noPages(url)
            }
            self.kind = .folder
            self.pdf = nil
            self.imageSource = nil
            self.imageFiles = files
            self.pageCount = files.count
            return
        }
        self.imageFiles = []
        let ext = url.pathExtension.lowercased()
        guard PageSource.supportedExtensions.contains(ext) else {
            throw PageSourceError.unsupported(url)
        }
        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else {
                throw PageSourceError.unreadable(url)
            }
            if document.isLocked {
                if let password, document.unlock(withPassword: password) {
                } else {
                    throw PageSourceError.encrypted(url)
                }
            }
            guard document.pageCount > 0 else {
                throw PageSourceError.noPages(url)
            }
            self.kind = .pdf
            self.pdf = document
            self.imageSource = nil
            self.pageCount = document.pageCount
        } else {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw PageSourceError.unreadable(url)
            }
            let count = CGImageSourceGetCount(source)
            guard count > 0 else {
                throw PageSourceError.noPages(url)
            }
            self.kind = .image
            self.pdf = nil
            self.imageSource = source
            self.pageCount = count
        }
    }

    public func embeddedText(page: Int) -> String? {
        guard let pdf, let pdfPage = pdf.page(at: page - 1) else {
            return nil
        }
        let text = pdfPage.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    public func hasEmbeddedText(samplePages: Int = 3) -> Bool {
        guard kind == .pdf else {
            return false
        }
        for page in 1...min(samplePages, pageCount) {
            if let text = embeddedText(page: page), text.count > 200 {
                return true
            }
        }
        return false
    }

    public func render(page: Int, longestSide: CGFloat = targetLongestSide) throws -> CIImage {
        guard page >= 1, page <= pageCount else {
            throw PageSourceError.pageOutOfRange(page)
        }
        switch kind {
        case .pdf:
            return try renderPDFPage(page, longestSide: longestSide)
        case .image:
            guard let imageSource else {
                throw PageSourceError.renderFailed(page)
            }
            return try renderImage(from: imageSource, index: page - 1, page: page, longestSide: longestSide)
        case .folder:
            guard let source = CGImageSourceCreateWithURL(imageFiles[page - 1] as CFURL, nil) else {
                throw PageSourceError.renderFailed(page)
            }
            return try renderImage(from: source, index: 0, page: page, longestSide: longestSide)
        }
    }

    public func pageLabel(_ page: Int) -> String {
        kind == .folder ? imageFiles[page - 1].lastPathComponent : "\(page)"
    }

    public static func imageFiles(in folder: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) && $0.pathExtension.lowercased() != "pdf" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func renderPDFPage(_ page: Int, longestSide: CGFloat) throws -> CIImage {
        guard let pdf, let pdfPage = pdf.page(at: page - 1) else {
            throw PageSourceError.renderFailed(page)
        }
        let box = pdfPage.bounds(for: .mediaBox)
        let quarterTurns = ((pdfPage.rotation % 360) + 360) % 360 / 90
        let pageWidth = quarterTurns % 2 == 0 ? box.width : box.height
        let pageHeight = quarterTurns % 2 == 0 ? box.height : box.width
        let scale = longestSide / max(pageWidth, pageHeight)
        let pixelWidth = Int((pageWidth * scale).rounded())
        let pixelHeight = Int((pageHeight * scale).rounded())

        guard let context = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else {
            throw PageSourceError.renderFailed(page)
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.concatenate(pdfPage.transform(for: .mediaBox))
        pdfPage.draw(with: .mediaBox, to: context)

        guard let cgImage = context.makeImage() else {
            throw PageSourceError.renderFailed(page)
        }
        return CIImage(cgImage: cgImage)
    }

    private func renderImage(from imageSource: CGImageSource, index: Int, page: Int, longestSide: CGFloat) throws -> CIImage {
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, index, nil) else {
            throw PageSourceError.renderFailed(page)
        }
        var image = CIImage(cgImage: cgImage)
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any]
        if let orientation = properties?[kCGImagePropertyOrientation] as? UInt32,
            let exif = CGImagePropertyOrientation(rawValue: orientation), exif != .up
        {
            image = image.oriented(exif)
            image = image.transformed(
                by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        }
        return resize(image, longestSide: longestSide)
    }
}

public func resize(_ image: CIImage, longestSide: CGFloat) -> CIImage {
    let longest = max(image.extent.width, image.extent.height)
    if longest == longestSide {
        return image
    }
    let filter = CIFilter(name: "CILanczosScaleTransform")!
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(longestSide / longest, forKey: kCIInputScaleKey)
    filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
    return filter.outputImage!
}

public func rotateCounterClockwise(_ image: CIImage, degrees: Int) -> CIImage {
    let normalised = ((degrees % 360) + 360) % 360
    if normalised == 0 {
        return image
    }
    let radians = CGFloat(normalised) * .pi / 180
    let rotated = image.transformed(by: CGAffineTransform(rotationAngle: radians))
    return rotated.transformed(
        by: CGAffineTransform(translationX: -rotated.extent.origin.x, y: -rotated.extent.origin.y))
}

public func savePNG(_ image: CIImage, to url: URL) throws {
    let context = CIContext()
    try context.writePNGRepresentation(
        of: image, to: url, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
}
