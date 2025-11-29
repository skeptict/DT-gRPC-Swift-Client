import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
#else
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#endif

// MARK: - Platform Image Extensions

extension PlatformImage {
    /// Create a platform image from Data
    public static func fromData(_ data: Data) -> PlatformImage? {
        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data)
        #endif
    }

    #if os(macOS)
    /// Convert to PNG data
    public func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
    #endif
    // Note: On iOS, UIImage already has pngData() built-in, so no extension needed

    /// Get the image dimensions in pixels
    public var pixelWidth: Int {
        #if os(macOS)
        guard let rep = representations.first else { return 0 }
        return rep.pixelsWide
        #else
        return Int(size.width * scale)
        #endif
    }

    public var pixelHeight: Int {
        #if os(macOS)
        guard let rep = representations.first else { return 0 }
        return rep.pixelsHigh
        #else
        return Int(size.height * scale)
        #endif
    }

    /// Get CGImage representation
    public var cgImageRepresentation: CGImage? {
        #if os(macOS)
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return cgImage
        #endif
    }
}

// MARK: - ImageHelpers

public struct ImageHelpers {

    // MARK: - Cross-Platform Methods

    /// Convert a platform image to PNG data
    public static func convertImageToData(_ image: PlatformImage) throws -> Data {
        guard let data = image.pngData() else {
            throw ImageError.conversionFailed
        }
        return data
    }

    /// Load image data from a URL
    public static func loadImageData(from url: URL) throws -> Data {
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else {
            throw ImageError.invalidImage
        }
        #else
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            throw ImageError.invalidImage
        }
        #endif
        return try convertImageToData(image)
    }

    /// Load image data from a file path
    public static func loadImageData(from path: String) throws -> Data {
        let url = URL(fileURLWithPath: path)
        return try loadImageData(from: url)
    }

    /// Convert Data to a platform image
    public static func dataToImage(_ data: Data) throws -> PlatformImage {
        guard let image = PlatformImage.fromData(data) else {
            throw ImageError.invalidData
        }
        return image
    }

    /// Resize an image to the specified size
    public static func resizeImage(_ image: PlatformImage, to size: CGSize) -> PlatformImage {
        #if os(macOS)
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        newImage.unlockFocus()
        return newImage
        #else
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        #endif
    }

    /// Scale image to fit within canvas dimensions while preserving aspect ratio
    /// Fills empty space with the specified background color, or leaves transparent if backgroundColor is nil
    public static func scaleImageToCanvas(_ image: PlatformImage, canvasWidth: Int, canvasHeight: Int, backgroundColor: PlatformColor?) -> PlatformImage {
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)

        #if os(macOS)
        let imageSize = image.size
        #else
        let imageSize = image.size
        #endif

        // Calculate aspect ratios
        let canvasAspect = CGFloat(canvasWidth) / CGFloat(canvasHeight)
        let imageAspect = imageSize.width / imageSize.height

        // Calculate scaled size that fits within canvas while preserving aspect ratio
        var scaledSize: CGSize
        if imageAspect > canvasAspect {
            // Image is wider than canvas - fit to width
            scaledSize = CGSize(width: canvasSize.width, height: canvasSize.width / imageAspect)
        } else {
            // Image is taller than canvas - fit to height
            scaledSize = CGSize(width: canvasSize.height * imageAspect, height: canvasSize.height)
        }

        // Center the scaled image on the canvas
        let x = (canvasSize.width - scaledSize.width) / 2
        let y = (canvasSize.height - scaledSize.height) / 2

        // Check if the image fills the entire canvas (no background needed)
        let imageFillsCanvas = abs(scaledSize.width - canvasSize.width) < 0.5 &&
                               abs(scaledSize.height - canvasSize.height) < 0.5

        DrawThingsClientLogger.debug("🔍 scaleImageToCanvas: image=\(imageSize), canvas=\(canvasSize), scaled=\(scaledSize), fills=\(imageFillsCanvas)")

        // If image fills canvas completely, no need to create new canvas with background
        if imageFillsCanvas {
            // Just resize the image if needed
            if abs(imageSize.width - canvasSize.width) < 0.5 &&
               abs(imageSize.height - canvasSize.height) < 0.5 {
                DrawThingsClientLogger.debug("✅ Image already correct size, returning original")
                return image
            } else {
                DrawThingsClientLogger.debug("✅ Resizing image without background")
                return resizeImage(image, to: canvasSize)
            }
        }

        DrawThingsClientLogger.debug("⚠️ Image needs letterboxing, adding background")

        #if os(macOS)
        let canvas = NSImage(size: canvasSize)
        canvas.lockFocus()

        // Fill background if color is provided, otherwise leave transparent
        if let backgroundColor = backgroundColor {
            backgroundColor.setFill()
            NSRect(origin: .zero, size: canvasSize).fill()
        } else {
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: canvasSize).fill()
        }

        // Draw scaled image centered
        image.draw(in: NSRect(x: x, y: y, width: scaledSize.width, height: scaledSize.height))

        canvas.unlockFocus()
        return canvas
        #else
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            // Fill background if color is provided
            if let backgroundColor = backgroundColor {
                backgroundColor.setFill()
                context.fill(CGRect(origin: .zero, size: canvasSize))
            }

            // Draw scaled image centered
            image.draw(in: CGRect(x: x, y: y, width: scaledSize.width, height: scaledSize.height))
        }
        #endif
    }

    // MARK: - DTTensor Conversion

    /// Convert a platform image to DTTensor format for Draw Things
    /// - Parameters:
    ///   - image: The source image
    ///   - forceRGB: If true, always output 3 channels (RGB) even if image has transparency
    /// - Returns: DTTensor data
    public static func imageToDTTensor(_ image: PlatformImage, forceRGB: Bool = false) throws -> Data {
        guard let cgImage = image.cgImageRepresentation else {
            throw ImageError.invalidImage
        }

        let width = cgImage.width
        let height = cgImage.height

        // Create RGBA bitmap context
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            throw ImageError.conversionFailed
        }

        // Draw the image into our buffer (RGBA format)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Check if image has any transparency
        var hasTransparency = false
        if !forceRGB {
            outerLoop: for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * bytesPerRow + x * 4
                    let alpha = pixelData[pixelIndex + 3] // Alpha is last in RGBA
                    if alpha < 255 {
                        hasTransparency = true
                        break outerLoop
                    }
                }
            }
        }

        let channels = (hasTransparency && !forceRGB) ? 4 : 3

        DrawThingsClientLogger.debug("🖼️ Converting image: \(width)x\(height), \(channels) channels, hasTransparency: \(hasTransparency), forceRGB: \(forceRGB)")

        // DTTensor format constants
        let CCV_TENSOR_CPU_MEMORY: UInt32 = 0x1
        let CCV_TENSOR_FORMAT_NHWC: UInt32 = 0x02
        let CCV_16F: UInt32 = 0x20000

        // Create header (17 uint32 values = 68 bytes)
        var header = [UInt32](repeating: 0, count: 17)
        header[0] = 0  // No compression
        header[1] = CCV_TENSOR_CPU_MEMORY
        header[2] = CCV_TENSOR_FORMAT_NHWC
        header[3] = CCV_16F
        header[4] = 0
        header[5] = 1  // N dimension
        header[6] = UInt32(height)
        header[7] = UInt32(width)
        header[8] = UInt32(channels)

        var tensorData = Data(count: 68 + width * height * channels * 2)

        // Write header
        tensorData.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
            let uint32Ptr = ptr.baseAddress!.assumingMemoryBound(to: UInt32.self)
            for i in 0..<9 {
                uint32Ptr[i] = header[i]
            }
        }

        // Convert RGBA pixel data to float16 tensor data in range [-1, 1]
        tensorData.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) in
            let tensorPixelPtr = outPtr.baseAddress!.advanced(by: 68)

            for y in 0..<height {
                for x in 0..<width {
                    let rgbaIndex = y * bytesPerRow + x * 4

                    for c in 0..<channels {
                        let uint8Value = pixelData[rgbaIndex + c]
                        let floatValue = (Float(uint8Value) / 255.0 * 2.0) - 1.0
                        let float16Value = Float16(floatValue)

                        let byteOffset = (y * width + x) * channels * 2 + c * 2
                        let bitPattern = float16Value.bitPattern
                        tensorPixelPtr.storeBytes(of: UInt8(bitPattern & 0xFF), toByteOffset: byteOffset, as: UInt8.self)
                        tensorPixelPtr.storeBytes(of: UInt8((bitPattern >> 8) & 0xFF), toByteOffset: byteOffset + 1, as: UInt8.self)
                    }
                }
            }
        }

        DrawThingsClientLogger.debug("✅ DTTensor created: \(tensorData.count) bytes")

        return tensorData
    }

    /// Convert DTTensor data to a platform image
    /// - Parameter tensorData: The DTTensor data from Draw Things
    /// - Returns: A platform image
    public static func dtTensorToImage(_ tensorData: Data) throws -> PlatformImage {
        guard tensorData.count >= 68 else {
            throw ImageError.invalidData
        }

        // Read header
        var header = [UInt32](repeating: 0, count: 17)
        tensorData.prefix(68).withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let uint32Ptr = ptr.bindMemory(to: UInt32.self)
            for i in 0..<17 {
                header[i] = uint32Ptr[i]
            }
        }

        let compressionFlag = header[0]
        let height = Int(header[6])
        let width = Int(header[7])
        let channels = Int(header[8])

        if compressionFlag == 1012247 {
            throw ImageError.compressionNotSupported
        }

        guard channels == 3 || channels == 4 || channels == 16 else {
            throw ImageError.conversionFailed
        }

        let pixelDataOffset = 68
        let expectedDataSize = pixelDataOffset + (width * height * channels * 2)

        guard tensorData.count >= expectedDataSize else {
            throw ImageError.invalidData
        }

        // Output RGB data
        var rgbData = Data(count: width * height * 3)

        tensorData.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
            let basePtr = rawPtr.baseAddress!.advanced(by: pixelDataOffset)
            let float16Ptr = basePtr.assumingMemoryBound(to: UInt16.self)

            rgbData.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) in
                let uint8Ptr = outPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)

                if channels == 16 {
                    // 16-channel latent space to RGB (Flux coefficients)
                    for i in 0..<(width * height) {
                        let v0 = Float(Float16(bitPattern: float16Ptr[i * 16 + 0]))
                        let v1 = Float(Float16(bitPattern: float16Ptr[i * 16 + 1]))
                        let v2 = Float(Float16(bitPattern: float16Ptr[i * 16 + 2]))
                        let v3 = Float(Float16(bitPattern: float16Ptr[i * 16 + 3]))
                        let v4 = Float(Float16(bitPattern: float16Ptr[i * 16 + 4]))
                        let v5 = Float(Float16(bitPattern: float16Ptr[i * 16 + 5]))
                        let v6 = Float(Float16(bitPattern: float16Ptr[i * 16 + 6]))
                        let v7 = Float(Float16(bitPattern: float16Ptr[i * 16 + 7]))
                        let v8 = Float(Float16(bitPattern: float16Ptr[i * 16 + 8]))
                        let v9 = Float(Float16(bitPattern: float16Ptr[i * 16 + 9]))
                        let v10 = Float(Float16(bitPattern: float16Ptr[i * 16 + 10]))
                        let v11 = Float(Float16(bitPattern: float16Ptr[i * 16 + 11]))
                        let v12 = Float(Float16(bitPattern: float16Ptr[i * 16 + 12]))
                        let v13 = Float(Float16(bitPattern: float16Ptr[i * 16 + 13]))
                        let v14 = Float(Float16(bitPattern: float16Ptr[i * 16 + 14]))
                        let v15 = Float(Float16(bitPattern: float16Ptr[i * 16 + 15]))

                        var rVal: Float = -0.0346 * v0 + 0.0034 * v1 + 0.0275 * v2 - 0.0174 * v3
                        rVal += 0.0859 * v4 + 0.0004 * v5 + 0.0405 * v6 - 0.0236 * v7
                        rVal += -0.0245 * v8 + 0.1008 * v9 - 0.0515 * v10 + 0.0428 * v11
                        rVal += 0.0817 * v12 - 0.1264 * v13 - 0.0280 * v14 - 0.1262 * v15 - 0.0329
                        let r = rVal * 127.5 + 127.5

                        var gVal: Float = 0.0244 * v0 + 0.0210 * v1 - 0.0668 * v2 + 0.0160 * v3
                        gVal += 0.0721 * v4 + 0.0383 * v5 + 0.0861 * v6 - 0.0185 * v7
                        gVal += 0.0250 * v8 + 0.0755 * v9 + 0.0201 * v10 - 0.0012 * v11
                        gVal += 0.0765 * v12 - 0.0522 * v13 - 0.0881 * v14 - 0.0982 * v15 - 0.0718
                        let g = gVal * 127.5 + 127.5

                        var bVal: Float = 0.0681 * v0 + 0.0687 * v1 - 0.0433 * v2 + 0.0617 * v3
                        bVal += 0.0329 * v4 + 0.0115 * v5 + 0.0915 * v6 - 0.0259 * v7
                        bVal += 0.1180 * v8 - 0.0421 * v9 + 0.0011 * v10 - 0.0036 * v11
                        bVal += 0.0749 * v12 - 0.1103 * v13 - 0.0499 * v14 - 0.0778 * v15 - 0.0851
                        let b = bVal * 127.5 + 127.5

                        uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
                        uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
                        uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
                    }
                } else if channels == 4 {
                    // 4-channel latent space to RGB (SDXL coefficients)
                    for i in 0..<(width * height) {
                        let v0 = Float(Float16(bitPattern: float16Ptr[i * 4 + 0]))
                        let v1 = Float(Float16(bitPattern: float16Ptr[i * 4 + 1]))
                        let v2 = Float(Float16(bitPattern: float16Ptr[i * 4 + 2]))
                        let v3 = Float(Float16(bitPattern: float16Ptr[i * 4 + 3]))

                        let r = 47.195 * v0 - 29.114 * v1 + 11.883 * v2 - 38.063 * v3 + 141.64
                        let g = 53.237 * v0 - 1.4623 * v1 + 12.991 * v2 - 28.043 * v3 + 127.46
                        let b = 58.182 * v0 + 4.3734 * v1 - 3.3735 * v2 - 26.722 * v3 + 114.5

                        uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r))
                        uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g))
                        uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b))
                    }
                } else {
                    // 3-channel RGB: Convert from [-1, 1] to [0, 255]
                    let pixelCount = width * height * channels
                    for i in 0..<pixelCount {
                        let float16Bits = float16Ptr[i]
                        let float16Value = Float16(bitPattern: float16Bits)
                        let floatValue = Float(float16Value)
                        let uint8Value = UInt8(clamping: Int(floatValue.isFinite ? (floatValue + 1.0) * 127.5 : 127.5))
                        uint8Ptr[i] = uint8Value
                    }
                }
            }
        }

        // Create platform image from RGB data
        return try createImageFromRGBData(rgbData, width: width, height: height)
    }

    /// Create a platform image from raw RGB data
    private static func createImageFromRGBData(_ rgbData: Data, width: Int, height: Int) throws -> PlatformImage {
        let bitsPerComponent = 8
        let bitsPerPixel = 24
        let bytesPerRow = width * 3

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ImageError.conversionFailed
        }

        let mutableData = rgbData

        guard let provider = CGDataProvider(data: mutableData as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bitsPerPixel: bitsPerPixel,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw ImageError.conversionFailed
        }

        #if os(macOS)
        let image = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        #else
        let image = UIImage(cgImage: cgImage)
        #endif

        return image
    }

    // MARK: - Transparency Helpers

    /// Check if an image has any transparent pixels
    public static func hasTransparency(_ image: PlatformImage) -> Bool {
        guard let cgImage = image.cgImageRepresentation else {
            return false
        }

        // Check if the image has an alpha channel
        let alphaInfo = cgImage.alphaInfo
        guard alphaInfo != .none && alphaInfo != .noneSkipFirst && alphaInfo != .noneSkipLast else {
            DrawThingsClientLogger.debug("🔍 hasTransparency: Image has no alpha channel, returning false")
            return false
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            return false
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Check if any pixel has alpha < 255
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * 4
                let alpha = pixelData[pixelIndex + 3] // Alpha is last in RGBA
                if alpha < 255 {
                    DrawThingsClientLogger.debug("🔍 hasTransparency: Found transparent pixel at (\(x), \(y)), alpha=\(alpha)")
                    return true
                }
            }
        }

        DrawThingsClientLogger.debug("🔍 hasTransparency: All pixels are opaque")
        return false
    }

    /// Fill transparent areas of an image with a fill color
    public static func fillTransparentAreas(_ image: PlatformImage, fillColor: PlatformColor) -> PlatformImage {
        #if os(macOS)
        let size = image.size
        let filled = NSImage(size: size)
        filled.lockFocus()

        fillColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(origin: .zero, size: size))

        filled.unlockFocus()
        return filled
        #else
        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            fillColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        #endif
    }

    // MARK: - Mask Creation

    /// Creates an inpainting mask from an image's alpha channel
    public static func createMaskFromAlpha(_ image: PlatformImage) throws -> Data {
        guard let cgImage = image.cgImageRepresentation else {
            throw ImageError.invalidImage
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            throw ImageError.conversionFailed
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Create mask with Draw Things mask format
        var maskData = Data(count: 68 + width * height)

        // Write mask header
        maskData.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
            let int32Ptr = ptr.baseAddress!.assumingMemoryBound(to: Int32.self)
            int32Ptr[0] = 0
            int32Ptr[1] = 1
            int32Ptr[2] = 1
            int32Ptr[3] = 4096
            int32Ptr[4] = 0
            int32Ptr[5] = Int32(height)
            int32Ptr[6] = Int32(width)
            int32Ptr[7] = 0
            int32Ptr[8] = 0
        }

        // Write mask data
        maskData.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
            let maskPtr = ptr.baseAddress!.advanced(by: 68).assumingMemoryBound(to: UInt8.self)

            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * bytesPerRow + x * 4
                    let alpha = pixelData[pixelIndex + 3] // Alpha is last in RGBA

                    // Transparent (alpha < 255) = 2 (inpaint)
                    // Opaque (alpha = 255) = 0 (preserve)
                    let maskValue: UInt8 = alpha < 255 ? 2 : 0
                    maskPtr[y * width + x] = maskValue
                }
            }
        }

        DrawThingsClientLogger.debug("🎭 Created inpainting mask from alpha channel: \(width)x\(height), size: \(maskData.count) bytes")

        return maskData
    }

    // MARK: - Legacy NSImage Methods (macOS only)

    #if os(macOS)
    @available(*, deprecated, renamed: "imageToDTTensor")
    public static func nsImageToDTTensor(_ image: NSImage, forceRGB: Bool = false) throws -> Data {
        return try imageToDTTensor(image, forceRGB: forceRGB)
    }

    @available(*, deprecated, renamed: "dtTensorToImage")
    public static func dtTensorToNSImage(_ tensorData: Data) throws -> NSImage {
        return try dtTensorToImage(tensorData)
    }

    @available(*, deprecated, renamed: "dataToImage")
    public static func dataToNSImage(_ data: Data) throws -> NSImage {
        return try dataToImage(data)
    }

    public static func createMaskFromImage(_ image: NSImage, threshold: Float = 0.5) throws -> Data {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw ImageError.invalidImage
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh

        let maskImage = NSImage(size: NSSize(width: width, height: height))
        maskImage.lockFocus()

        for y in 0..<height {
            for x in 0..<width {
                if let color = bitmap.colorAt(x: x, y: y) {
                    let gray = Float(color.redComponent * 0.299 + color.greenComponent * 0.587 + color.blueComponent * 0.114)
                    let maskValue = gray > threshold ? 1.0 : 0.0
                    NSColor(white: CGFloat(maskValue), alpha: 1.0).setFill()
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
        }

        maskImage.unlockFocus()

        return try convertImageToData(maskImage)
    }
    #endif
}

// MARK: - Image Errors

public enum ImageError: Error, LocalizedError {
    case invalidImage
    case invalidData
    case conversionFailed
    case fileNotFound
    case compressionNotSupported

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image format or corrupted image"
        case .invalidData:
            return "Invalid image data"
        case .conversionFailed:
            return "Failed to convert image to desired format"
        case .fileNotFound:
            return "Image file not found"
        case .compressionNotSupported:
            return "Compressed image format not yet supported. Please disable compression in Draw Things server settings."
        }
    }
}
