import Foundation
import Cocoa

public struct ImageHelpers {
    
    public static func convertImageToData(_ image: NSImage, format: NSBitmapImageRep.FileType = .png) throws -> Data {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw ImageError.invalidImage
        }
        
        guard let data = bitmap.representation(using: format, properties: [:]) else {
            throw ImageError.conversionFailed
        }
        
        return data
    }
    
    public static func loadImageData(from url: URL) throws -> Data {
        guard let image = NSImage(contentsOf: url) else {
            throw ImageError.invalidImage
        }
        
        return try convertImageToData(image)
    }
    
    public static func loadImageData(from path: String) throws -> Data {
        let url = URL(fileURLWithPath: path)
        return try loadImageData(from: url)
    }
    
    public static func dataToNSImage(_ data: Data) throws -> NSImage {
        guard let image = NSImage(data: data) else {
            throw ImageError.invalidData
        }
        return image
    }
    
    public static func resizeImage(_ image: NSImage, to size: CGSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        newImage.unlockFocus()
        return newImage
    }

    /// Scale image to fit within canvas dimensions while preserving aspect ratio
    /// Fills empty space with the specified background color, or leaves transparent if backgroundColor is nil
    public static func scaleImageToCanvas(_ image: NSImage, canvasWidth: Int, canvasHeight: Int, backgroundColor: NSColor?) -> NSImage {
        // For outpainting mode (backgroundColor is nil), we need to handle this differently
        // Instead of transparency, use a neutral color that the model can work with
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)
        let imageSize = image.size

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
                // Already the right size
                DrawThingsClientLogger.debug("✅ Image already correct size, returning original")
                return image
            } else {
                // Need to resize
                DrawThingsClientLogger.debug("✅ Resizing image without background")
                let resized = NSImage(size: canvasSize)
                resized.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: canvasSize))
                resized.unlockFocus()
                return resized
            }
        }

        DrawThingsClientLogger.debug("⚠️ Image needs letterboxing, adding background")

        // Image doesn't fill canvas - need background
        let canvas = NSImage(size: canvasSize)
        canvas.lockFocus()

        // Fill background if color is provided, otherwise leave transparent
        if let backgroundColor = backgroundColor {
            backgroundColor.setFill()
            NSRect(origin: .zero, size: canvasSize).fill()
        } else {
            // Clear to transparent
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: canvasSize).fill()
        }

        // Draw scaled image centered
        image.draw(in: NSRect(x: x, y: y, width: scaledSize.width, height: scaledSize.height))

        canvas.unlockFocus()

        return canvas
    }
    
    /// Convert DTTensor format (from Draw Things server) to NSImage
    /// DTTensor format:
    /// - 68-byte header containing width, height, channels, compression flag
    /// - Float16 RGB data (optionally compressed)
    /// - Values in range [-1, 1] need to be converted to [0, 255]
    /// - Parameter forceRGB: If true, always output 3 channels (RGB) even if image has transparency
    public static func nsImageToDTTensor(_ image: NSImage, forceRGB: Bool = false) throws -> Data {
        // Get the bitmap representation directly without TIFF conversion
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageError.invalidImage
        }

        let width = cgImage.width
        let height = cgImage.height

        // Create ARGB bitmap (standard on macOS with premultipliedFirst)
        let bytesPerRow = width * 4  // 4 bytes per pixel (ARGB)
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            throw ImageError.conversionFailed
        }

        // Draw the image into our buffer
        // CGContext with our settings already handles the coordinate system correctly
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Check if image has any transparency
        var hasTransparency = false
        if !forceRGB {
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * bytesPerRow + x * 4
                    let alpha = pixelData[pixelIndex] // Alpha is first in ARGB
                    if alpha < 255 {
                        hasTransparency = true
                        break
                    }
                }
                if hasTransparency { break }
            }
        }

        let channels = (hasTransparency && !forceRGB) ? 4 : 3  // RGBA for transparency, RGB otherwise (unless forced)
        DrawThingsClientLogger.debug("🖼️ Converting image: \(width)x\(height), \(channels) channels, hasTransparency: \(hasTransparency), forceRGB: \(forceRGB)")

        // Debug: Check first few pixels (ARGB format)
        var hexBytes = ""
        for i in 0..<min(16, pixelData.count) {
            hexBytes += String(format: "%02x ", pixelData[i])
        }
        DrawThingsClientLogger.debug("First 16 bytes (4 ARGB pixels): \(hexBytes)")

        // DTTensor format constants (from ccv_nnc)
        let CCV_TENSOR_CPU_MEMORY: UInt32 = 0x1
        let CCV_TENSOR_FORMAT_NHWC: UInt32 = 0x02
        let CCV_16F: UInt32 = 0x20000

        // Create header (17 uint32 values = 68 bytes, but we only use first 9)
        // Based on: struct.pack_into("<9I", image_bytes, 0, 0, CCV_TENSOR_CPU_MEMORY, CCV_TENSOR_FORMAT_NHWC, CCV_16F, 0, 1, height, width, channels)
        var header = [UInt32](repeating: 0, count: 17)
        header[0] = 0  // No compression (fpzip compression flag would be 1012247)
        header[1] = CCV_TENSOR_CPU_MEMORY
        header[2] = CCV_TENSOR_FORMAT_NHWC
        header[3] = CCV_16F
        header[4] = 0  // reserved
        header[5] = 1  // N dimension (batch size)
        header[6] = UInt32(height)  // H dimension
        header[7] = UInt32(width)   // W dimension
        header[8] = UInt32(channels) // C dimension

        var tensorData = Data(count: 68 + width * height * channels * 2)

        // Write header
        tensorData.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
            let uint32Ptr = ptr.baseAddress!.assumingMemoryBound(to: UInt32.self)
            for i in 0..<9 {
                uint32Ptr[i] = header[i]
            }
        }

        // Convert ARGB pixel data to RGB float16 tensor data in range [-1, 1]
        tensorData.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) in
            let tensorPixelPtr = outPtr.baseAddress!.advanced(by: 68)
            var debugPixelCount = 0

            for y in 0..<height {
                for x in 0..<width {
                    let argbIndex = y * bytesPerRow + x * 4  // 4 bytes per pixel (ARGB)
                    let tensorOffset = 68 + (y * width + x) * (channels * 2)  // channels * 2 bytes per pixel

                    // Extract RGB(A) from ARGB (A at index 0, R at 1, G at 2, B at 3)
                    let channelOffsets = channels == 4 ? [1, 2, 3, 0] : [1, 2, 3]  // RGBA or RGB
                    for c in 0..<channels {
                        let uint8Value = pixelData[argbIndex + channelOffsets[c]]
                        // Convert from [0, 255] to [-1, 1]: v = pixel[c] / 255 * 2 - 1
                        let floatValue = (Float(uint8Value) / 255.0 * 2.0) - 1.0
                        let float16Value = Float16(floatValue)

                        // Debug first pixel
                        if debugPixelCount < channels {
                            let channelName = channels == 4 ? ["R", "G", "B", "A"][c] : ["R", "G", "B"][c]
                            let bitPattern = float16Value.bitPattern
                            let byte0 = UInt8(bitPattern & 0xFF)
                            let byte1 = UInt8((bitPattern >> 8) & 0xFF)
                            DrawThingsClientLogger.debug("🔬 Pixel 0 \(channelName): uint8=\(uint8Value) -> float=\(floatValue) -> float16=\(float16Value) -> bytes=[\(String(format: "%02x", byte0)) \(String(format: "%02x", byte1))]")
                            debugPixelCount += 1
                        }

                        // Write Float16 in little-endian format (matching Python's struct.pack "<e")
                        let bitPattern = float16Value.bitPattern
                        let byteOffset = tensorOffset - 68 + c * 2

                        // Write as little-endian: low byte first, high byte second
                        let byte0 = UInt8(bitPattern & 0xFF)
                        let byte1 = UInt8((bitPattern >> 8) & 0xFF)
                        tensorPixelPtr.storeBytes(of: byte0, toByteOffset: byteOffset, as: UInt8.self)
                        tensorPixelPtr.storeBytes(of: byte1, toByteOffset: byteOffset + 1, as: UInt8.self)
                    }
                }
            }
        }

        DrawThingsClientLogger.debug("✅ DTTensor created: \(tensorData.count) bytes")

        // Debug: Print first 100 bytes as hex
        let debugBytes = tensorData.prefix(100).map { String(format: "%02x", $0) }.joined(separator: " ")
        DrawThingsClientLogger.debug("📊 First 100 bytes: \(debugBytes)")

        return tensorData
    }

    public static func dtTensorToNSImage(_ tensorData: Data) throws -> NSImage {
        guard tensorData.count >= 68 else {
            throw ImageError.invalidData
        }

        // Read header (17 uint32 values = 68 bytes)
        let headerData = tensorData.prefix(68)
        var header = [UInt32](repeating: 0, count: 17)
        headerData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let uint32Ptr = ptr.bindMemory(to: UInt32.self)
            for i in 0..<17 {
                header[i] = uint32Ptr[i]
            }
        }

        // Extract metadata from header
        let compressionFlag = header[0]
        let height = Int(header[6])
        let width = Int(header[7])
        let channels = Int(header[8])

        DrawThingsClientLogger.debug("📊 DTTensor: \(width)x\(height), \(channels) channels, compressed: \(compressionFlag == 1012247)")

        // Check for compression
        let isCompressed = (compressionFlag == 1012247)

        if isCompressed {
            DrawThingsClientLogger.debug("⚠️ Image is compressed with fpzip - decompression not yet implemented")
            DrawThingsClientLogger.debug("💡 Workaround: Disable compression in Draw Things server settings")
            throw ImageError.compressionNotSupported
        }

        guard channels == 3 || channels == 4 || channels == 16 else {
            DrawThingsClientLogger.debug("⚠️ Unsupported channel count: \(channels). Only RGB (3), RGBA (4), and 16-channel latents are supported.")
            throw ImageError.conversionFailed
        }

        // Extract Float16 data (2 bytes per value)
        let pixelDataOffset = 68
        let pixelCount = width * height * channels
        let expectedDataSize = pixelDataOffset + (pixelCount * 2)

        guard tensorData.count >= expectedDataSize else {
            DrawThingsClientLogger.debug("⚠️ Data size mismatch: got \(tensorData.count), expected \(expectedDataSize)")
            throw ImageError.invalidData
        }

        // Output will always be RGB (3 channels)
        var rgbData = Data(count: width * height * 3)

        tensorData.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
            let basePtr = rawPtr.baseAddress!.advanced(by: pixelDataOffset)
            let float16Ptr = basePtr.assumingMemoryBound(to: UInt16.self)

            rgbData.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) in
                let uint8Ptr = outPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)

                if channels == 16 {
                    // 16-channel latent space to RGB conversion (Flux coefficients)
                    // Based on Draw Things ImageConverter.swift for Flux/HiDream models
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

                        // Flux latent-to-RGB coefficients (from Draw Things source)
                        // Red channel
                        var rVal: Float = -0.0346 * v0 + 0.0034 * v1 + 0.0275 * v2 - 0.0174 * v3
                        rVal += 0.0859 * v4 + 0.0004 * v5 + 0.0405 * v6 - 0.0236 * v7
                        rVal += -0.0245 * v8 + 0.1008 * v9 - 0.0515 * v10 + 0.0428 * v11
                        rVal += 0.0817 * v12 - 0.1264 * v13 - 0.0280 * v14 - 0.1262 * v15 - 0.0329
                        let r = rVal * 127.5 + 127.5

                        // Green channel
                        var gVal: Float = 0.0244 * v0 + 0.0210 * v1 - 0.0668 * v2 + 0.0160 * v3
                        gVal += 0.0721 * v4 + 0.0383 * v5 + 0.0861 * v6 - 0.0185 * v7
                        gVal += 0.0250 * v8 + 0.0755 * v9 + 0.0201 * v10 - 0.0012 * v11
                        gVal += 0.0765 * v12 - 0.0522 * v13 - 0.0881 * v14 - 0.0982 * v15 - 0.0718
                        let g = gVal * 127.5 + 127.5

                        // Blue channel
                        var bVal: Float = 0.0681 * v0 + 0.0687 * v1 - 0.0433 * v2 + 0.0617 * v3
                        bVal += 0.0329 * v4 + 0.0115 * v5 + 0.0915 * v6 - 0.0259 * v7
                        bVal += 0.1180 * v8 - 0.0421 * v9 + 0.0011 * v10 - 0.0036 * v11
                        bVal += 0.0749 * v12 - 0.1103 * v13 - 0.0499 * v14 - 0.0778 * v15 - 0.0851
                        let b = bVal * 127.5 + 127.5

                        // Clamp to valid RGB range
                        uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
                        uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
                        uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
                    }
                } else if channels == 4 {
                    // 4-channel latent space to RGB conversion (SDXL coefficients)
                    // Based on Draw Things ImageConverter.swift
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
                    for i in 0..<pixelCount {
                        let float16Bits = float16Ptr[i]
                        let float16Value = Float16(bitPattern: float16Bits)
                        let floatValue = Float(float16Value)
                        // Handle NaN/infinity by defaulting to mid-gray
                        let uint8Value = UInt8(clamping: Int(floatValue.isFinite ? (floatValue + 1.0) * 127.5 : 127.5))
                        uint8Ptr[i] = uint8Value
                    }
                }
            }
        }

        // Create NSImage from RGB data
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 3,
            bitsPerPixel: 24
        ) else {
            throw ImageError.conversionFailed
        }

        // Copy RGB data to bitmap
        rgbData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            if let bitmapData = bitmap.bitmapData {
                ptr.copyBytes(to: UnsafeMutableRawBufferPointer(start: bitmapData, count: rgbData.count))
            }
        }

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)

        return image
    }

    /// Check if an image has any transparent pixels
    /// - Parameter image: The image to check
    /// - Returns: true if any pixel has alpha < 255, false otherwise
    public static func hasTransparency(_ image: NSImage) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pixelData = bitmap.bitmapData else {
            return false
        }

        // If image doesn't have an alpha channel, it's definitely opaque
        guard bitmap.hasAlpha else {
            DrawThingsClientLogger.debug("🔍 hasTransparency: Image has no alpha channel, returning false")
            return false
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let bytesPerRow = bitmap.bytesPerRow
        let samplesPerPixel = bitmap.samplesPerPixel

        DrawThingsClientLogger.debug("🔍 hasTransparency: Scanning \(width)x\(height), \(samplesPerPixel) samples/pixel, bytesPerRow=\(bytesPerRow)")

        // Determine alpha channel position (usually first in ARGB or last in RGBA)
        let alphaPosition: Int
        if bitmap.bitmapFormat.contains(.alphaFirst) {
            alphaPosition = 0  // ARGB
        } else {
            alphaPosition = samplesPerPixel - 1  // RGBA
        }

        // Check if any pixel has alpha < 255
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * samplesPerPixel
                let alpha = pixelData[pixelIndex + alphaPosition]
                if alpha < 255 {
                    DrawThingsClientLogger.debug("🔍 hasTransparency: Found transparent pixel at (\(x), \(y)), alpha=\(alpha)")
                    return true  // Found transparent pixel
                }
            }
        }

        DrawThingsClientLogger.debug("🔍 hasTransparency: All pixels are opaque")
        return false  // All pixels are opaque
    }

    /// Creates an inpainting mask from an image's alpha channel
    /// - Parameter image: The source image with alpha channel
    /// - Returns: Mask data in Draw Things format: header (9x Int32) + UInt8 mask values
    ///   - Mask values: 0 = retain/preserve, 2 = inpaint with config strength
    /// Fill transparent areas of an image with a neutral gray color
    /// This is useful for inpainting - transparent areas become gray which gives the
    /// inpainting algorithm something to work from
    public static func fillTransparentAreas(_ image: NSImage, fillColor: NSColor = NSColor(white: 0.5, alpha: 1.0)) -> NSImage {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return image
        }

        // Create a new image with filled transparent areas
        let size = image.size
        let filled = NSImage(size: size)
        filled.lockFocus()

        // Fill with the fill color
        fillColor.setFill()
        NSRect(origin: .zero, size: size).fill()

        // Draw the original image on top (opaque areas will cover, transparent won't)
        image.draw(in: NSRect(origin: .zero, size: size))

        filled.unlockFocus()

        return filled
    }

    public static func createMaskFromAlpha(_ image: NSImage) throws -> Data {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pixelData = bitmap.bitmapData else {
            throw ImageError.invalidImage
        }

        guard bitmap.hasAlpha else {
            throw ImageError.invalidImage
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let bytesPerRow = bitmap.bytesPerRow
        let samplesPerPixel = bitmap.samplesPerPixel

        // Determine alpha channel position
        let alphaPosition: Int
        if bitmap.bitmapFormat.contains(.alphaFirst) {
            alphaPosition = 0  // ARGB
        } else {
            alphaPosition = samplesPerPixel - 1  // RGBA
        }

        // Create mask with special Draw Things mask format
        // From Draw Things docs: header is [0, 1, 1, 4096, 0, height, width, 0, 0] as Int32
        // Total size: 68 bytes header + width*height bytes data
        var maskData = Data(count: 68 + width * height)

        // Write mask header (9 Int32 values = 36 bytes, padded to 68 bytes)
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
            // Remaining bytes up to 68 are already zeroed
        }

        // Write mask data (UInt8 values) starting at offset 68
        // 0 = retain/preserve (opaque pixels)
        // 2 = inpaint with config strength (transparent pixels)
        maskData.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
            let maskPtr = ptr.baseAddress!.advanced(by: 68).assumingMemoryBound(to: UInt8.self)

            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * bytesPerRow + x * samplesPerPixel
                    let alpha = pixelData[pixelIndex + alphaPosition]

                    // Transparent (alpha < 255) = 2 (inpaint)
                    // Opaque (alpha = 255) = 0 (preserve)
                    let maskValue: UInt8 = alpha < 255 ? 2 : 0
                    maskPtr[y * width + x] = maskValue
                }
            }
        }

        // Count transparent vs opaque pixels for debugging
        var transparentCount = 0
        var opaqueCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * samplesPerPixel
                let alpha = pixelData[pixelIndex + alphaPosition]
                if alpha < 255 {
                    transparentCount += 1
                } else {
                    opaqueCount += 1
                }
            }
        }

        DrawThingsClientLogger.debug("🎭 Created inpainting mask from alpha channel: \(width)x\(height), size: \(maskData.count) bytes")
        DrawThingsClientLogger.debug("🎭 Mask stats: \(transparentCount) transparent pixels (value 2), \(opaqueCount) opaque pixels (value 0)")

        // Print first 50 bytes as hex for verification
        let previewBytes = min(50, maskData.count)
        let hexString = maskData.prefix(previewBytes).map { String(format: "%02x", $0) }.joined(separator: " ")
        DrawThingsClientLogger.debug("🎭 Mask header (first \(previewBytes) bytes): \(hexString)")

        return maskData
    }

    public static func createMaskFromImage(_ image: NSImage, threshold: Float = 0.5) throws -> Data {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw ImageError.invalidImage
        }
        
        // Convert to grayscale and create binary mask
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
}

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