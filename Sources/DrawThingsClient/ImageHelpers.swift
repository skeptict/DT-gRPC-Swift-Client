//
//  ImageHelpers.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

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

// MARK: - Latent Model Family

/// Model families for latent-to-RGB preview conversion.
///
/// Different model architectures use different latent space representations,
/// requiring specific coefficients to convert previews to displayable RGB images.
public enum LatentModelFamily: String, Sendable, CaseIterable {
    /// Stable Diffusion 1.x, 2.x (4-channel latent)
    case sd1
    /// Stable Diffusion XL (4-channel latent)
    case sdxl
    /// Stable Diffusion 3 (16-channel latent)
    case sd3
    /// Flux.1 models (16-channel latent)
    case flux
    /// HunyuanVideo (16-channel latent)
    case hunyuanVideo
    /// Qwen Image Edit (16-channel latent, same coefficients as Wan 2.1)
    case qwen
    /// Z Image (16-channel latent, uses Flux-like coefficients)
    case zImage
    /// Wan 2.1 models (16-channel latent)
    case wan21
    /// Wan 2.2 5B model (48-channel latent)
    case wan22
    /// Unknown model - will use default coefficients
    case unknown

    /// Detect model family from model filename or version string.
    ///
    /// - Parameter modelNameOrVersion: The model filename (e.g., "flux1-dev-q8p.gguf") or version string (e.g., "qwenImage", "flux1")
    /// - Returns: The detected model family
    public static func detect(from modelNameOrVersion: String) -> LatentModelFamily {
        let lowercased = modelNameOrVersion.lowercased()

        // First check for exact version strings from Draw Things (case-insensitive)
        // These come from CheckpointModel.version field
        switch lowercased {
        case "qwenimage":
            return .qwen
        case "zimage":
            return .zImage
        case "flux1", "hidreami1":
            return .flux
        case "wan21_1_3b", "wan21_14b":
            return .wan21
        case "wan22_5b":
            return .wan22
        case "hunyuanvideo":
            return .hunyuanVideo
        case "sd3", "sd3large":
            return .sd3
        case "sdxlbase", "sdxlrefiner", "ssd1b":
            return .sdxl
        case "v1", "v2":
            return .sd1
        default:
            break
        }

        // Fall back to substring matching for filenames
        if lowercased.contains("flux") || lowercased.contains("hidream") {
            return .flux
        }
        if lowercased.contains("zimage") || lowercased.contains("z_image") || lowercased.contains("z-image") {
            return .zImage
        }
        if lowercased.contains("qwen") {
            return .qwen
        }
        if lowercased.contains("wan") {
            // Distinguish Wan 2.2 (5B) from Wan 2.1
            if lowercased.contains("wan22") || lowercased.contains("wan_2.2") || lowercased.contains("wan-2.2") || lowercased.contains("5b") {
                return .wan22
            }
            return .wan21
        }
        if lowercased.contains("hunyuan") && lowercased.contains("video") {
            return .hunyuanVideo
        }
        if lowercased.contains("sd3") || lowercased.contains("sd_3") || lowercased.contains("stable-diffusion-3") {
            return .sd3
        }
        if lowercased.contains("sdxl") || lowercased.contains("sd_xl") || lowercased.contains("xl_base") || lowercased.contains("xl_refiner") {
            return .sdxl
        }
        if lowercased.contains("sd_") || lowercased.contains("v1-") || lowercased.contains("v2-") {
            return .sd1
        }

        // Default to unknown for unrecognized models
        return .unknown
    }

    /// The number of latent channels for this model family.
    public var latentChannels: Int {
        switch self {
        case .sd1, .sdxl:
            return 4
        case .sd3, .flux, .hunyuanVideo, .qwen, .zImage, .wan21:
            return 16
        case .wan22:
            return 48
        case .unknown:
            return 16  // Default assumption for unknown
        }
    }
}

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
                        let floatValue: Float = (Float(uint8Value) / 255.0 * 2.0) - 1.0
                        let bitPattern: UInt16 = floatToFloat16Bits(floatValue)

                        let byteOffset = (y * width + x) * channels * 2 + c * 2
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
    /// - Parameters:
    ///   - tensorData: The DTTensor data from Draw Things
    ///   - modelFamily: Optional model family for correct latent-to-RGB conversion (defaults to .flux for 16-channel)
    /// - Returns: A platform image
    public static func dtTensorToImage(_ tensorData: Data, modelFamily: LatentModelFamily? = nil) throws -> PlatformImage {
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
        let formatFlag = header[2]  // 0x01 = NCHW (planar), 0x02 = NHWC (interleaved)
        let height = Int(header[6])
        let width = Int(header[7])
        let channels = Int(header[8])

        if compressionFlag == 1012247 {
            throw ImageError.compressionNotSupported
        }

        guard channels == 3 || channels == 4 || channels == 16 || channels == 48 else {
            DrawThingsClientLogger.error("dtTensorToImage: unsupported channel count \(channels)")
            throw ImageError.conversionFailed
        }

        let pixelDataOffset = 68
        let expectedDataSize = pixelDataOffset + (width * height * channels * 2)

        guard tensorData.count >= expectedDataSize else {
            throw ImageError.invalidData
        }

        let isNCHW = formatFlag != 0x02  // Anything other than NHWC is treated as NCHW
        NSLog("[dtTensor] %dx%d, %d channels, format=0x%x (%@), modelFamily=%@, tensorSize=%d bytes", width, height, channels, formatFlag, isNCHW ? "NCHW" : "NHWC", modelFamily?.rawValue ?? "nil", tensorData.count)
        DrawThingsClientLogger.debug("dtTensorToImage: \(width)x\(height), \(channels) channels, modelFamily=\(modelFamily?.rawValue ?? "nil")")

        // Output RGB data
        var rgbData = Data(count: width * height * 3)

        tensorData.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
            let basePtr = rawPtr.baseAddress!.advanced(by: pixelDataOffset)
            let float16Ptr = basePtr.assumingMemoryBound(to: UInt16.self)

            rgbData.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) in
                let uint8Ptr = outPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)

                if channels == 48 {
                    // 48-channel latent space to RGB (Wan 2.2 5B coefficients)
                    DrawThingsClientLogger.debug("dtTensorToImage: using 48-channel Wan 2.2 conversion")
                    convert48ChannelToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                } else if channels == 16 {
                    // 16-channel latent space to RGB - use model-specific coefficients
                    let family = modelFamily ?? .flux
                    switch family {
                    case .qwen, .wan21:
                        DrawThingsClientLogger.debug("dtTensorToImage: using Qwen/Wan21 16-channel conversion")
                        convertQwenWan21ToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    case .sd3:
                        DrawThingsClientLogger.debug("dtTensorToImage: using SD3 16-channel conversion")
                        convertSD3ToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    case .hunyuanVideo:
                        DrawThingsClientLogger.debug("dtTensorToImage: using HunyuanVideo 16-channel conversion")
                        convertHunyuanVideoToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    case .flux, .zImage, .unknown:
                        // Z Image uses Flux-like latent space
                        DrawThingsClientLogger.debug("dtTensorToImage: using Flux 16-channel conversion (family=\(family))")
                        convertFluxToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    default:
                        // Default to Flux coefficients for other 16-channel models
                        DrawThingsClientLogger.debug("dtTensorToImage: using Flux 16-channel conversion (default for \(family))")
                        convertFluxToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    }
                } else if channels == 4 {
                    DrawThingsClientLogger.debug("dtTensorToImage: using 4-channel SDXL conversion")
                    // 4-channel latent space to RGB (SDXL coefficients)
                    convert4ChannelToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                } else {
                    // 3-channel decoded RGB — auto-detect layout and value range
                    let totalValues = width * height * channels
                    let planeSize = width * height

                    // 1) Sample values to determine range
                    let sampleCount = min(2000, totalValues)
                    let sampleStep = max(1, totalValues / sampleCount)
                    var negCount = 0
                    var minVal: Float = .infinity
                    var maxVal: Float = -.infinity
                    for idx in stride(from: 0, to: totalValues, by: sampleStep) {
                        let v = f16ToFloat(float16Ptr, idx)
                        guard v.isFinite else { continue }
                        if v < -0.01 { negCount += 1 }
                        minVal = min(minVal, v)
                        maxVal = max(maxVal, v)
                    }
                    let sampledCount = (totalValues + sampleStep - 1) / sampleStep
                    let hasNegatives = negCount > sampledCount / 10  // >10% negative → [-1,1]

                    // 2) Auto-detect NCHW vs NHWC via spatial autocorrelation
                    //    NCHW: adjacent indices = adjacent pixels in same channel (high correlation)
                    //    NHWC: stride-3 indices = adjacent pixels in same channel
                    let checkPixels = min(200, width - 1)
                    var nchwDiff: Float = 0  // adjacent indices diff (NCHW hypothesis)
                    var nhwcDiff: Float = 0  // stride-3 diff (NHWC hypothesis)
                    for i in 0..<checkPixels {
                        nchwDiff += abs(f16ToFloat(float16Ptr, i) - f16ToFloat(float16Ptr, i + 1))
                        let a = i * 3, b = (i + 1) * 3
                        if b < totalValues {
                            nhwcDiff += abs(f16ToFloat(float16Ptr, a) - f16ToFloat(float16Ptr, b))
                        }
                    }
                    let autoNCHW = nchwDiff < nhwcDiff

                    // Trust the header format flag — the server explicitly sets it
                    let useNCHW = isNCHW

                    NSLog("[dtTensor] 3ch detect: neg=%d/%d min=%.4f max=%.4f hasNeg=%d nchwD=%.2f nhwcD=%.2f autoNCHW=%d headerNCHW=%d → useNCHW=%d",
                          negCount, sampledCount, minVal, maxVal, hasNegatives ? 1 : 0,
                          nchwDiff, nhwcDiff, autoNCHW ? 1 : 0, isNCHW ? 1 : 0, useNCHW ? 1 : 0)

                    // Write header dump to file for diagnostics
                    var diag = "[dtTensor] Diagnostic at \(Date())\n"
                    diag += "Header (17 x UInt32):\n"
                    for hi in 0..<17 { diag += "  [\(hi)] = \(header[hi])  (0x\(String(header[hi], radix: 16)))\n" }
                    diag += "Dims: \(width)x\(height)x\(channels)\n"
                    diag += "Sample: neg=\(negCount)/\(sampledCount), min=\(minVal), max=\(maxVal), hasNeg=\(hasNegatives)\n"
                    diag += "Correlation: nchwDiff=\(nchwDiff), nhwcDiff=\(nhwcDiff), autoNCHW=\(autoNCHW)\n"
                    diag += "Decision: useNCHW=\(useNCHW)\n"
                    diag += "First 20 float16 values:\n"
                    for vi in 0..<min(20, totalValues) { diag += "  [\(vi)] = \(f16ToFloat(float16Ptr, vi))\n" }
                    try? diag.write(toFile: "/tmp/dts_tensor_diag.log", atomically: true, encoding: .utf8)

                    if useNCHW {
                        // NCHW planar: [RRR...][GGG...][BBB...]
                        for i in 0..<planeSize {
                            let r = f16ToFloat(float16Ptr, i)
                            let g = f16ToFloat(float16Ptr, i + planeSize)
                            let b = f16ToFloat(float16Ptr, i + planeSize * 2)
                            if hasNegatives {
                                uint8Ptr[i * 3 + 0] = UInt8(clamping: Int((r + 1.0) * 127.5))
                                uint8Ptr[i * 3 + 1] = UInt8(clamping: Int((g + 1.0) * 127.5))
                                uint8Ptr[i * 3 + 2] = UInt8(clamping: Int((b + 1.0) * 127.5))
                            } else {
                                uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(min(max(r, 0), 1) * 255))
                                uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(min(max(g, 0), 1) * 255))
                                uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(min(max(b, 0), 1) * 255))
                            }
                        }
                    } else {
                        // NHWC interleaved: [RGB][RGB]...
                        if hasNegatives {
                            convert3ChannelToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: totalValues)
                        } else {
                            for i in 0..<totalValues {
                                let v = f16ToFloat(float16Ptr, i)
                                uint8Ptr[i] = UInt8(clamping: Int(v.isFinite ? min(max(v, 0), 1) * 255 : 0))
                            }
                        }
                    }
                }
            }
        }

        // Create platform image from RGB data
        return try createImageFromRGBData(rgbData, width: width, height: height)
    }

    // MARK: - Model-Specific Latent Conversion Functions

    /// Helper to convert Float16 bit pattern to Float - works on all platforms
    @inline(__always)
    private static func f16ToFloat(_ ptr: UnsafePointer<UInt16>, _ index: Int) -> Float {
        let bits: UInt16 = ptr[index]
        return float16BitsToFloat(bits)
    }

    /// Convert Float16 bit pattern to Float32 manually (platform-independent)
    @inline(__always)
    private static func float16BitsToFloat(_ h: UInt16) -> Float {
        let sign = UInt32((h >> 15) & 0x1)
        let exponent = UInt32((h >> 10) & 0x1F)
        let mantissa = UInt32(h & 0x3FF)

        var result: UInt32

        if exponent == 0 {
            if mantissa == 0 {
                // Zero
                result = sign << 31
            } else {
                // Denormalized number - convert to normalized
                var exp = Int32(-14)
                var mant = mantissa
                while (mant & 0x400) == 0 {
                    mant <<= 1
                    exp -= 1
                }
                mant &= 0x3FF
                result = (sign << 31) | (UInt32(Int32(127) + exp) << 23) | (mant << 13)
            }
        } else if exponent == 31 {
            // Infinity or NaN
            result = (sign << 31) | 0x7F800000 | (mantissa << 13)
        } else {
            // Normalized number
            result = (sign << 31) | ((exponent + 112) << 23) | (mantissa << 13)
        }

        return Float(bitPattern: result)
    }

    /// Convert Float32 to Float16 bit pattern manually (platform-independent)
    @inline(__always)
    private static func floatToFloat16Bits(_ f: Float) -> UInt16 {
        let bits = f.bitPattern
        let sign = UInt16((bits >> 31) & 0x1)
        let exponent = Int32((bits >> 23) & 0xFF)
        let mantissa = bits & 0x7FFFFF

        var result: UInt16

        if exponent == 0 {
            // Zero or denormalized (becomes zero in float16)
            result = sign << 15
        } else if exponent == 255 {
            // Infinity or NaN
            result = (sign << 15) | 0x7C00 | UInt16((mantissa >> 13) & 0x3FF)
        } else {
            // Normalized number
            let newExp = exponent - 127 + 15
            if newExp <= 0 {
                // Underflow to zero
                result = sign << 15
            } else if newExp >= 31 {
                // Overflow to infinity
                result = (sign << 15) | 0x7C00
            } else {
                result = (sign << 15) | (UInt16(newExp) << 10) | UInt16((mantissa >> 13) & 0x3FF)
            }
        }

        return result
    }

    /// Convert 4-channel SDXL latent to RGB
    private static func convert4ChannelToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 4
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)

            let r: Float = 47.195 * v0 - 29.114 * v1 + 11.883 * v2 - 38.063 * v3 + 141.64
            let g: Float = 53.237 * v0 - 1.4623 * v1 + 12.991 * v2 - 28.043 * v3 + 127.46
            let b: Float = 58.182 * v0 + 4.3734 * v1 - 3.3735 * v2 - 26.722 * v3 + 114.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 3-channel NHWC interleaved RGB from [-1, 1] to [0, 255]
    private static func convert3ChannelToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let floatValue = f16ToFloat(float16Ptr, i)
            let uint8Value = UInt8(clamping: Int(floatValue.isFinite ? (floatValue + 1.0) * 127.5 : 127.5))
            uint8Ptr[i] = uint8Value
        }
    }

    /// Convert 16-channel Flux latent to RGB
    private static func convertFluxToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 16
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)
            let v4 = f16ToFloat(float16Ptr, base + 4)
            let v5 = f16ToFloat(float16Ptr, base + 5)
            let v6 = f16ToFloat(float16Ptr, base + 6)
            let v7 = f16ToFloat(float16Ptr, base + 7)
            let v8 = f16ToFloat(float16Ptr, base + 8)
            let v9 = f16ToFloat(float16Ptr, base + 9)
            let v10 = f16ToFloat(float16Ptr, base + 10)
            let v11 = f16ToFloat(float16Ptr, base + 11)
            let v12 = f16ToFloat(float16Ptr, base + 12)
            let v13 = f16ToFloat(float16Ptr, base + 13)
            let v14 = f16ToFloat(float16Ptr, base + 14)
            let v15 = f16ToFloat(float16Ptr, base + 15)

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
    }

    /// Convert 16-channel SD3 latent to RGB
    private static func convertSD3ToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 16
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)
            let v4 = f16ToFloat(float16Ptr, base + 4)
            let v5 = f16ToFloat(float16Ptr, base + 5)
            let v6 = f16ToFloat(float16Ptr, base + 6)
            let v7 = f16ToFloat(float16Ptr, base + 7)
            let v8 = f16ToFloat(float16Ptr, base + 8)
            let v9 = f16ToFloat(float16Ptr, base + 9)
            let v10 = f16ToFloat(float16Ptr, base + 10)
            let v11 = f16ToFloat(float16Ptr, base + 11)
            let v12 = f16ToFloat(float16Ptr, base + 12)
            let v13 = f16ToFloat(float16Ptr, base + 13)
            let v14 = f16ToFloat(float16Ptr, base + 14)
            let v15 = f16ToFloat(float16Ptr, base + 15)

            var rVal: Float = -0.0922 * v0 + 0.0311 * v1 + 0.1994 * v2 + 0.0856 * v3
            rVal += 0.0587 * v4 - 0.0006 * v5 + 0.0978 * v6 - 0.0042 * v7
            rVal += -0.0194 * v8 - 0.0488 * v9 + 0.0922 * v10 - 0.0278 * v11
            rVal += 0.0332 * v12 - 0.0069 * v13 - 0.0596 * v14 - 0.1448 * v15 + 0.2394
            let r = rVal * 127.5 + 127.5

            var gVal: Float = -0.0175 * v0 + 0.0633 * v1 + 0.0927 * v2 + 0.0339 * v3
            gVal += 0.0272 * v4 + 0.1104 * v5 + 0.0306 * v6 + 0.1038 * v7
            gVal += 0.0020 * v8 + 0.0130 * v9 + 0.0988 * v10 + 0.0524 * v11
            gVal += 0.0456 * v12 - 0.0030 * v13 - 0.0465 * v14 - 0.1463 * v15 + 0.2135
            let g = gVal * 127.5 + 127.5

            var bVal: Float = 0.0749 * v0 + 0.0954 * v1 + 0.0458 * v2 + 0.0902 * v3
            bVal += -0.0496 * v4 + 0.0309 * v5 + 0.0427 * v6 + 0.1358 * v7
            bVal += 0.0669 * v8 - 0.0268 * v9 + 0.0951 * v10 - 0.0542 * v11
            bVal += 0.0895 * v12 - 0.0810 * v13 - 0.0293 * v14 - 0.1189 * v15 + 0.1925
            let b = bVal * 127.5 + 127.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 16-channel HunyuanVideo latent to RGB
    private static func convertHunyuanVideoToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 16
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)
            let v4 = f16ToFloat(float16Ptr, base + 4)
            let v5 = f16ToFloat(float16Ptr, base + 5)
            let v6 = f16ToFloat(float16Ptr, base + 6)
            let v7 = f16ToFloat(float16Ptr, base + 7)
            let v8 = f16ToFloat(float16Ptr, base + 8)
            let v9 = f16ToFloat(float16Ptr, base + 9)
            let v10 = f16ToFloat(float16Ptr, base + 10)
            let v11 = f16ToFloat(float16Ptr, base + 11)
            let v12 = f16ToFloat(float16Ptr, base + 12)
            let v13 = f16ToFloat(float16Ptr, base + 13)
            let v14 = f16ToFloat(float16Ptr, base + 14)
            let v15 = f16ToFloat(float16Ptr, base + 15)

            var rVal: Float = -0.0395 * v0 + 0.0696 * v1 + 0.0135 * v2 + 0.0108 * v3
            rVal += -0.0209 * v4 - 0.0804 * v5 - 0.0991 * v6 - 0.0646 * v7
            rVal += -0.0696 * v8 - 0.0799 * v9 + 0.1166 * v10 + 0.1165 * v11
            rVal += -0.2315 * v12 - 0.0270 * v13 - 0.0616 * v14 + 0.0249 * v15 + 0.0249
            let r = rVal * 127.5 + 127.5

            var gVal: Float = -0.0331 * v0 + 0.0795 * v1 - 0.0945 * v2 - 0.0250 * v3
            gVal += 0.0032 * v4 - 0.0254 * v5 + 0.0271 * v6 - 0.0422 * v7
            gVal += -0.0595 * v8 - 0.0208 * v9 + 0.1627 * v10 + 0.0432 * v11
            gVal += -0.1920 * v12 + 0.0401 * v13 - 0.0997 * v14 - 0.0469 * v15 - 0.0192
            let g = gVal * 127.5 + 127.5

            var bVal: Float = 0.0445 * v0 + 0.0518 * v1 - 0.0282 * v2 - 0.0765 * v3
            bVal += 0.0224 * v4 - 0.0639 * v5 - 0.0669 * v6 - 0.0400 * v7
            bVal += -0.0894 * v8 - 0.0375 * v9 + 0.0962 * v10 + 0.0407 * v11
            bVal += -0.1355 * v12 - 0.0821 * v13 - 0.0727 * v14 - 0.1703 * v15 - 0.0761
            let b = bVal * 127.5 + 127.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 16-channel Qwen/Wan 2.1 latent to RGB
    private static func convertQwenWan21ToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 16
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)
            let v4 = f16ToFloat(float16Ptr, base + 4)
            let v5 = f16ToFloat(float16Ptr, base + 5)
            let v6 = f16ToFloat(float16Ptr, base + 6)
            let v7 = f16ToFloat(float16Ptr, base + 7)
            let v8 = f16ToFloat(float16Ptr, base + 8)
            let v9 = f16ToFloat(float16Ptr, base + 9)
            let v10 = f16ToFloat(float16Ptr, base + 10)
            let v11 = f16ToFloat(float16Ptr, base + 11)
            let v12 = f16ToFloat(float16Ptr, base + 12)
            let v13 = f16ToFloat(float16Ptr, base + 13)
            let v14 = f16ToFloat(float16Ptr, base + 14)
            let v15 = f16ToFloat(float16Ptr, base + 15)

            var rVal: Float = -0.1299 * v0 + 0.0671 * v1 + 0.3568 * v2 + 0.0372 * v3
            rVal += 0.0313 * v4 + 0.0296 * v5 - 0.3477 * v6 + 0.0166 * v7
            rVal += -0.0412 * v8 - 0.1293 * v9 + 0.0680 * v10 + 0.0032 * v11
            rVal += -0.1251 * v12 + 0.0060 * v13 + 0.3477 * v14 + 0.1984 * v15 - 0.1835
            let r = rVal * 127.5 + 127.5

            var gVal: Float = -0.1692 * v0 + 0.0406 * v1 + 0.2548 * v2 + 0.2344 * v3
            gVal += 0.0189 * v4 - 0.0956 * v5 - 0.4059 * v6 + 0.1902 * v7
            gVal += 0.0267 * v8 + 0.0740 * v9 + 0.3019 * v10 + 0.0581 * v11
            gVal += 0.0927 * v12 - 0.0633 * v13 + 0.2275 * v14 + 0.0913 * v15 - 0.0868
            let g = gVal * 127.5 + 127.5

            var bVal: Float = 0.2932 * v0 + 0.0442 * v1 + 0.1747 * v2 + 0.1420 * v3
            bVal += -0.0328 * v4 - 0.0665 * v5 - 0.2925 * v6 + 0.1975 * v7
            bVal += -0.1364 * v8 + 0.1636 * v9 + 0.1128 * v10 + 0.0639 * v11
            bVal += 0.1699 * v12 + 0.0005 * v13 + 0.2950 * v14 + 0.1861 * v15 - 0.336
            let b = bVal * 127.5 + 127.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 48-channel Wan 2.2 5B latent to RGB
    private static func convert48ChannelToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            // Read all 48 channels
            let base = i * 48
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)
            let v4 = f16ToFloat(float16Ptr, base + 4)
            let v5 = f16ToFloat(float16Ptr, base + 5)
            let v6 = f16ToFloat(float16Ptr, base + 6)
            let v7 = f16ToFloat(float16Ptr, base + 7)
            let v8 = f16ToFloat(float16Ptr, base + 8)
            let v9 = f16ToFloat(float16Ptr, base + 9)
            let v10 = f16ToFloat(float16Ptr, base + 10)
            let v11 = f16ToFloat(float16Ptr, base + 11)
            let v12 = f16ToFloat(float16Ptr, base + 12)
            let v13 = f16ToFloat(float16Ptr, base + 13)
            let v14 = f16ToFloat(float16Ptr, base + 14)
            let v15 = f16ToFloat(float16Ptr, base + 15)
            let v16 = f16ToFloat(float16Ptr, base + 16)
            let v17 = f16ToFloat(float16Ptr, base + 17)
            let v18 = f16ToFloat(float16Ptr, base + 18)
            let v19 = f16ToFloat(float16Ptr, base + 19)
            let v20 = f16ToFloat(float16Ptr, base + 20)
            let v21 = f16ToFloat(float16Ptr, base + 21)
            let v22 = f16ToFloat(float16Ptr, base + 22)
            let v23 = f16ToFloat(float16Ptr, base + 23)
            let v24 = f16ToFloat(float16Ptr, base + 24)
            let v25 = f16ToFloat(float16Ptr, base + 25)
            let v26 = f16ToFloat(float16Ptr, base + 26)
            let v27 = f16ToFloat(float16Ptr, base + 27)
            let v28 = f16ToFloat(float16Ptr, base + 28)
            let v29 = f16ToFloat(float16Ptr, base + 29)
            let v30 = f16ToFloat(float16Ptr, base + 30)
            let v31 = f16ToFloat(float16Ptr, base + 31)
            let v32 = f16ToFloat(float16Ptr, base + 32)
            let v33 = f16ToFloat(float16Ptr, base + 33)
            let v34 = f16ToFloat(float16Ptr, base + 34)
            let v35 = f16ToFloat(float16Ptr, base + 35)
            let v36 = f16ToFloat(float16Ptr, base + 36)
            let v37 = f16ToFloat(float16Ptr, base + 37)
            let v38 = f16ToFloat(float16Ptr, base + 38)
            let v39 = f16ToFloat(float16Ptr, base + 39)
            let v40 = f16ToFloat(float16Ptr, base + 40)
            let v41 = f16ToFloat(float16Ptr, base + 41)
            let v42 = f16ToFloat(float16Ptr, base + 42)
            let v43 = f16ToFloat(float16Ptr, base + 43)
            let v44 = f16ToFloat(float16Ptr, base + 44)
            let v45 = f16ToFloat(float16Ptr, base + 45)
            let v46 = f16ToFloat(float16Ptr, base + 46)
            let v47 = f16ToFloat(float16Ptr, base + 47)

            // Wan 2.2 5B coefficients
            var rVal: Float = 0.0119 * v0 - 0.1062 * v1 + 0.0140 * v2 - 0.0813 * v3
            rVal += 0.0656 * v4 + 0.0264 * v5 + 0.0295 * v6 - 0.0244 * v7
            rVal += 0.0443 * v8 - 0.0465 * v9 + 0.0359 * v10 - 0.0776 * v11
            rVal += 0.0564 * v12 + 0.0006 * v13 - 0.0319 * v14 - 0.0268 * v15
            rVal += 0.0539 * v16 - 0.0359 * v17 - 0.0285 * v18 + 0.1041 * v19
            rVal += -0.0086 * v20 + 0.0390 * v21 + 0.0069 * v22 + 0.0006 * v23
            rVal += 0.0313 * v24 - 0.1454 * v25 + 0.0714 * v26 - 0.0304 * v27
            rVal += 0.0401 * v28 - 0.0758 * v29 + 0.0568 * v30 - 0.0055 * v31
            rVal += 0.0239 * v32 - 0.0663 * v33 - 0.0416 * v34 + 0.0166 * v35
            rVal += -0.0211 * v36 + 0.1833 * v37 - 0.0368 * v38 - 0.3441 * v39
            rVal += -0.0479 * v40 - 0.0660 * v41 - 0.0101 * v42 - 0.0690 * v43
            rVal += -0.0145 * v44 + 0.0421 * v45 + 0.0504 * v46 - 0.0837 * v47
            let r = rVal * 127.5 + 127.5

            var gVal: Float = 0.0103 * v0 - 0.0504 * v1 + 0.0409 * v2 - 0.0677 * v3
            gVal += 0.0851 * v4 + 0.0463 * v5 + 0.0326 * v6 - 0.0270 * v7
            gVal += -0.0102 * v8 - 0.0090 * v9 + 0.0236 * v10 + 0.0854 * v11
            gVal += 0.0264 * v12 + 0.0594 * v13 - 0.0542 * v14 + 0.0024 * v15
            gVal += 0.0265 * v16 - 0.0312 * v17 - 0.1032 * v18 + 0.0537 * v19
            gVal += -0.0374 * v20 + 0.0670 * v21 + 0.0144 * v22 - 0.0167 * v23
            gVal += -0.0574 * v24 - 0.0902 * v25 + 0.0827 * v26 - 0.0574 * v27
            gVal += 0.0384 * v28 - 0.0297 * v29 + 0.1307 * v30 - 0.0310 * v31
            gVal += -0.0305 * v32 - 0.0673 * v33 - 0.0047 * v34 + 0.0112 * v35
            gVal += 0.0011 * v36 + 0.1466 * v37 + 0.0370 * v38 - 0.3543 * v39
            gVal += -0.0489 * v40 - 0.0153 * v41 + 0.0068 * v42 - 0.0452 * v43
            gVal += 0.0041 * v44 + 0.0451 * v45 - 0.0483 * v46 + 0.0168 * v47
            let g = gVal * 127.5 + 127.5

            var bVal: Float = 0.0046 * v0 + 0.0165 * v1 + 0.0491 * v2 + 0.0607 * v3
            bVal += 0.0808 * v4 + 0.0912 * v5 + 0.0590 * v6 + 0.0025 * v7
            bVal += 0.0288 * v8 - 0.0205 * v9 + 0.0082 * v10 + 0.1048 * v11
            bVal += 0.0561 * v12 + 0.0418 * v13 - 0.0637 * v14 + 0.0260 * v15
            bVal += 0.0358 * v16 - 0.0287 * v17 - 0.1237 * v18 + 0.0622 * v19
            bVal += -0.0051 * v20 + 0.2863 * v21 + 0.0082 * v22 + 0.0079 * v23
            bVal += -0.0232 * v24 - 0.0481 * v25 + 0.0447 * v26 - 0.0196 * v27
            bVal += 0.0204 * v28 - 0.0014 * v29 + 0.1372 * v30 - 0.0380 * v31
            bVal += 0.0325 * v32 - 0.0140 * v33 - 0.0023 * v34 - 0.0093 * v35
            bVal += 0.0331 * v36 + 0.2250 * v37 + 0.0295 * v38 - 0.2008 * v39
            bVal += -0.0420 * v40 + 0.0800 * v41 + 0.0156 * v42 - 0.0927 * v43
            bVal += 0.0015 * v44 + 0.0373 * v45 - 0.0356 * v46 + 0.0055 * v47
            let b = bVal * 127.5 + 127.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Create a platform image from raw RGB data
    private static func createImageFromRGBData(_ rgbData: Data, width: Int, height: Int) throws -> PlatformImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ImageError.conversionFailed
        }

        #if os(macOS)
        // macOS: Create CGImage directly from RGB data
        let bitsPerComponent = 8
        let bitsPerPixel = 24
        let bytesPerRow = width * 3
        let cfData = rgbData as CFData

        guard let provider = CGDataProvider(data: cfData),
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
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        #else
        // iOS: Convert RGB to RGBA since iOS handles RGBA better
        // Add alpha channel (fully opaque) to the RGB data
        var rgbaData = Data(capacity: width * height * 4)
        for i in 0..<(width * height) {
            let rgbOffset = i * 3
            rgbaData.append(rgbData[rgbOffset])     // R
            rgbaData.append(rgbData[rgbOffset + 1]) // G
            rgbaData.append(rgbData[rgbOffset + 2]) // B
            rgbaData.append(255)                     // A (fully opaque)
        }

        let bitsPerComponent = 8
        let bitsPerPixel = 32
        let bytesPerRow = width * 4
        let cfData = rgbaData as CFData

        guard let provider = CGDataProvider(data: cfData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bitsPerPixel: bitsPerPixel,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw ImageError.conversionFailed
        }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        #endif
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
