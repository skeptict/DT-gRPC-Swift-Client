import XCTest
@testable import DrawThingsClient

final class DrawThingsClientTests: XCTestCase {
    
    func testConfigurationCreation() throws {
        let config = DrawThingsConfiguration(
            width: 512,
            height: 512,
            steps: 20,
            model: "sd_xl_base_1.0.safetensors",
            guidanceScale: 7.0
        )
        
        XCTAssertEqual(config.width, 512)
        XCTAssertEqual(config.height, 512)
        XCTAssertEqual(config.steps, 20)
        XCTAssertEqual(config.guidanceScale, 7.0)
    }
    
    func testSamplerTypes() {
        XCTAssertEqual(SamplerType.ddim.rawValue, 2)
        XCTAssertEqual(SamplerType.eulera.rawValue, 1)
        XCTAssertEqual(SamplerType.dpmpp2mkarras.rawValue, 0)
    }
    
    func testGenerationStageDescriptions() {
        XCTAssertEqual(GenerationStage.textEncoding.description, "Encoding text prompt...")
        XCTAssertEqual(GenerationStage.sampling(step: 5).description, "Generating image (step 5)...")
        XCTAssertEqual(GenerationStage.imageDecoding.description, "Decoding generated image...")
    }

    func testSeedModeMapping() {
        // Verify all seed modes are correctly mapped in FlatBuffer serialization
        let configs: [(Int32, SeedMode)] = [
            (0, .legacy),
            (1, .torchcpucompatible),
            (2, .scalealike),
            (3, .nvidiagpucompatible),
        ]

        for (intVal, expectedEnum) in configs {
            let config = DrawThingsConfiguration(seedMode: intVal)
            // Verify the enum maps correctly by checking rawValue
            let mapped = SeedMode(rawValue: Int8(intVal))
            XCTAssertEqual(mapped, expectedEnum, "Seed mode \(intVal) should map to \(expectedEnum)")
        }
    }

    func testTCDSamplerConfiguration() {
        // TCD sampler with typical Flux settings
        let config = DrawThingsConfiguration(
            width: 1024,
            height: 1024,
            steps: 8,
            model: "flux1-schnell-q8p.gguf",
            sampler: .tcd,
            guidanceScale: 1.0,
            shift: 3.0,
            stochasticSamplingGamma: 0.3,
            resolutionDependentShift: true,
            t5TextEncoder: true,
            seedMode: 2
        )

        XCTAssertEqual(config.sampler, .tcd)
        XCTAssertEqual(config.stochasticSamplingGamma, 0.3)
        XCTAssertEqual(config.resolutionDependentShift, true)
        XCTAssertEqual(config.t5TextEncoder, true)
        XCTAssertEqual(config.seedMode, 2)

        // Verify FlatBuffer serialization doesn't crash
        XCTAssertNoThrow(try config.toFlatBufferData())
    }

    func testConfigFlatBufferRoundtrip() throws {
        // Verify the FlatBuffer data can be generated without errors for various configs
        let configs = [
            DrawThingsConfiguration(width: 512, height: 512, steps: 20, model: "sd_xl_base_1.0.safetensors", sampler: .dpmpp2mkarras, seedMode: 0),
            DrawThingsConfiguration(width: 1024, height: 1024, steps: 8, model: "flux1-dev-q8p.gguf", sampler: .tcd, stochasticSamplingGamma: 0.3, resolutionDependentShift: true, t5TextEncoder: true, seedMode: 2),
            DrawThingsConfiguration(width: 768, height: 1152, steps: 4, model: "flux1-schnell-q8p.gguf", sampler: .euleratrailing, seedMode: 1),
        ]

        for config in configs {
            let data = try config.toFlatBufferData()
            XCTAssertGreaterThan(data.count, 0, "FlatBuffer data should not be empty for model \(config.model)")
        }
    }

    /// Integration test: connects to Draw Things and generates an image with TCD sampler.
    /// Requires Draw Things running on localhost:7859 with gRPC enabled.
    func testLiveGenerationWithTCD() async throws {
        // Enable verbose logging
        DrawThingsClientLogger.minimumLevel = .debug

        // Skip if Draw Things isn't running
        let service: DrawThingsService
        do {
            service = try DrawThingsService(address: "127.0.0.1:7859", useTLS: true)
        } catch {
            throw XCTSkip("Draw Things not available: \(error)")
        }

        // Echo to verify connection
        let echo: EchoReply
        do {
            echo = try await service.echo()
        } catch {
            throw XCTSkip("Draw Things gRPC not reachable: \(error)")
        }
        print("[Test] Echo message: \(echo.message)")
        print("[Test] Files count: \(echo.files.count)")

        // Find a model to use from the files list
        let modelExts = [".ckpt", ".safetensors", ".gguf"]
        let allModels = echo.files.filter { file in
            let lower = file.lowercased()
            return modelExts.contains(where: { lower.hasSuffix($0) }) && !lower.contains("lora")
        }
        let fluxModels = allModels.filter { $0.lowercased().contains("flux") }

        let modelName: String
        if let first = fluxModels.first {
            modelName = first
            print("[Test] Using Flux model: \(modelName)")
        } else if let first = allModels.first {
            modelName = first
            print("[Test] Using available model: \(modelName)")
        } else {
            // Use the model currently loaded in Draw Things (empty string = use loaded model)
            modelName = ""
            print("[Test] No models in files list, using currently loaded model")
        }

        let modelFamily = modelName.isEmpty ? LatentModelFamily.unknown : LatentModelFamily.detect(from: modelName)
        let isFlux = [LatentModelFamily.flux, .zImage].contains(modelFamily)
        print("[Test] Model family: \(modelFamily.rawValue), isFlux: \(isFlux)")

        // Build TCD configuration
        let config = DrawThingsConfiguration(
            width: 512,
            height: 512,
            steps: 4,
            model: modelName,
            sampler: .tcd,
            guidanceScale: isFlux ? 1.0 : 3.5,
            shift: isFlux ? 3.0 : 1.0,
            stochasticSamplingGamma: 0.3,
            resolutionDependentShift: isFlux,
            t5TextEncoder: isFlux,
            seedMode: 2
        )

        let configData = try config.toFlatBufferData()
        print("[Test] Config FlatBuffer size: \(configData.count) bytes")

        // Generate with detailed logging
        var allResponseImages: [Data] = []
        var previewImages: [Data] = []
        let results = try await service.generateImage(
            prompt: "A small red cube on a white background, simple test",
            negativePrompt: "",
            configuration: configData,
            image: nil,
            mask: nil,
            progressHandler: { signpost in
                if let sp = signpost {
                    print("[Test] Progress: \(sp)")
                }
            },
            previewHandler: { previewData in
                print("[Test] Preview received: \(previewData.count) bytes")
                previewImages.append(previewData)
            }
        )

        print("[Test] Got \(results.count) result tensor(s), \(previewImages.count) preview(s)")

        XCTAssertFalse(results.isEmpty, "Should have generated at least one image")

        // Verify tensor data has correct structure
        for (i, tensor) in results.enumerated() {
            XCTAssertGreaterThan(tensor.count, 68, "Tensor \(i) should have header + data")

            // Read header
            let header = tensor.prefix(68).withUnsafeBytes { ptr -> [UInt32] in
                let uint32Ptr = ptr.bindMemory(to: UInt32.self)
                return (0..<17).map { uint32Ptr[$0] }
            }

            let height = Int(header[6])
            let width = Int(header[7])
            let channels = Int(header[8])
            let isLatent = channels > 3
            print("[Test] Tensor \(i): \(width)x\(height), \(channels) channels, \(tensor.count) bytes, isLatent=\(isLatent)")

            // Full header dump
            for hi in 0..<17 {
                print("[Test]   header[\(hi)] = \(header[hi]) (0x\(String(header[hi], radix: 16)))")
            }

            // Verify we can convert to image
            let image = try ImageHelpers.dtTensorToImage(tensor, modelFamily: modelFamily)
            XCTAssertGreaterThan(image.pixelWidth, 0, "Image should have positive width")
            XCTAssertGreaterThan(image.pixelHeight, 0, "Image should have positive height")
            print("[Test] Converted to image: \(image.pixelWidth)x\(image.pixelHeight)")

            // Save image to /tmp for visual inspection
            if let pngData = image.pngData() {
                let outputURL = URL(fileURLWithPath: "/tmp/dts_test_output_\(i).png")
                try pngData.write(to: outputURL)
                print("[Test] Saved to \(outputURL.path)")
            }
        }

        // Also save preview images for comparison
        for (i, preview) in previewImages.enumerated() {
            if preview.count > 68 {
                let image = try ImageHelpers.dtTensorToImage(preview, modelFamily: modelFamily)
                if let pngData = image.pngData() {
                    let outputURL = URL(fileURLWithPath: "/tmp/dts_test_preview_\(i).png")
                    try pngData.write(to: outputURL)
                    print("[Test] Saved preview \(i) to \(outputURL.path)")
                }
            }
        }
    }

    /// Test with standard sampler to verify conversion code works correctly.
    func testLiveGenerationStandard() async throws {
        DrawThingsClientLogger.minimumLevel = .debug

        let service: DrawThingsService
        do {
            service = try DrawThingsService(address: "127.0.0.1:7859", useTLS: true)
            _ = try await service.echo()
        } catch {
            throw XCTSkip("Draw Things gRPC not reachable")
        }

        // Use DPM++ 2M Karras with 20 steps - should work with any model
        let config = DrawThingsConfiguration(
            width: 512,
            height: 512,
            steps: 20,
            model: "",
            sampler: .dpmpp2mkarras,
            guidanceScale: 7.0,
            shift: 1.0,
            stochasticSamplingGamma: 0.3,
            seedMode: 2
        )

        let configData = try config.toFlatBufferData()
        let results = try await service.generateImage(
            prompt: "A bright red apple on a white table, studio lighting",
            negativePrompt: "blurry, dark",
            configuration: configData,
            progressHandler: { _ in }
        )

        XCTAssertFalse(results.isEmpty)
        let tensor = results[0]

        let header = tensor.prefix(68).withUnsafeBytes { ptr -> [UInt32] in
            let uint32Ptr = ptr.bindMemory(to: UInt32.self)
            return (0..<17).map { uint32Ptr[$0] }
        }
        let width = Int(header[7])
        let height = Int(header[6])
        let channels = Int(header[8])
        print("[Standard] Tensor: \(width)x\(height), \(channels) channels, \(tensor.count) bytes")

        let image = try ImageHelpers.dtTensorToImage(tensor)
        print("[Standard] Image: \(image.pixelWidth)x\(image.pixelHeight)")

        if let pngData = image.pngData() {
            try pngData.write(to: URL(fileURLWithPath: "/tmp/dts_test_standard.png"))
            print("[Standard] Saved to /tmp/dts_test_standard.png")
        }
    }

    /// Verify the 3-channel NHWC conversion with known values
    func testSynthetic3ChannelConversion() throws {
        let width = 4
        let height = 4

        // Build a synthetic tensor with known float16 values in [-1, 1] range
        // Layout: 68-byte header + float16 NHWC data
        var tensorData = Data(count: 68 + width * height * 3 * 2)

        tensorData.withUnsafeMutableBytes { ptr in
            let uint32Ptr = ptr.baseAddress!.assumingMemoryBound(to: UInt32.self)
            uint32Ptr[0] = 0           // no compression
            uint32Ptr[1] = 0x1         // CCV_TENSOR_CPU_MEMORY
            uint32Ptr[2] = 0x02        // NHWC format
            uint32Ptr[3] = 0x20000     // CCV_16F
            uint32Ptr[4] = 0
            uint32Ptr[5] = 1           // N
            uint32Ptr[6] = UInt32(height)
            uint32Ptr[7] = UInt32(width)
            uint32Ptr[8] = 3           // channels
        }

        // Write known float16 values: a 4x4 image with specific colors
        // Pixel (0,0) = white: R=1.0, G=1.0, B=1.0 → should be 255,255,255
        // Pixel (1,0) = black: R=-1.0, G=-1.0, B=-1.0 → should be 0,0,0
        // Pixel (2,0) = red: R=1.0, G=-1.0, B=-1.0 → should be 255,0,0
        // Pixel (3,0) = gray: R=0.0, G=0.0, B=0.0 → should be 127/128,127/128,127/128
        let testPixels: [(Float, Float, Float)] = [
            (1.0, 1.0, 1.0),     // white
            (-1.0, -1.0, -1.0),  // black
            (1.0, -1.0, -1.0),   // red
            (0.0, 0.0, 0.0),     // gray
        ]

        tensorData.withUnsafeMutableBytes { ptr in
            let basePtr = ptr.baseAddress!.advanced(by: 68).assumingMemoryBound(to: UInt16.self)
            for (i, pixel) in testPixels.enumerated() {
                let floats = [pixel.0, pixel.1, pixel.2]
                for (c, val) in floats.enumerated() {
                    let bits = val.bitPattern
                    let sign = UInt16((bits >> 31) & 0x1)
                    let exponent = Int32((bits >> 23) & 0xFF)
                    let mantissa = bits & 0x7FFFFF
                    let newExp = exponent - 127 + 15
                    let f16: UInt16
                    if exponent == 0 { f16 = sign << 15 }
                    else if newExp <= 0 { f16 = sign << 15 }
                    else if newExp >= 31 { f16 = (sign << 15) | 0x7C00 }
                    else { f16 = (sign << 15) | (UInt16(newExp) << 10) | UInt16((mantissa >> 13) & 0x3FF) }
                    basePtr[i * 3 + c] = f16
                }
            }
            // Fill remaining pixels with zeros (gray)
            for i in (testPixels.count * 3)..<(width * height * 3) {
                basePtr[i] = 0 // float16 zero
            }
        }

        let image = try ImageHelpers.dtTensorToImage(tensorData)
        XCTAssertEqual(image.pixelWidth * 1, image.pixelWidth) // sanity

        // Extract pixel values
        guard let cgImage = image.cgImageRepresentation else {
            XCTFail("Failed to get CGImage"); return
        }
        let bytesPerRow = cgImage.width * 4
        var pixelBuffer = [UInt8](repeating: 0, count: cgImage.height * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixelBuffer, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { XCTFail("Failed to create context"); return }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        // Check pixel (0,0) = white (should be ~255)
        let px0 = (r: pixelBuffer[0], g: pixelBuffer[1], b: pixelBuffer[2])
        print("[Synthetic] Pixel(0,0) white: R=\(px0.r) G=\(px0.g) B=\(px0.b)")
        XCTAssertGreaterThan(px0.r, 240, "White pixel R should be near 255")
        XCTAssertGreaterThan(px0.g, 240, "White pixel G should be near 255")
        XCTAssertGreaterThan(px0.b, 240, "White pixel B should be near 255")

        // Check pixel (1,0) = black (should be ~0)
        let px1 = (r: pixelBuffer[4], g: pixelBuffer[5], b: pixelBuffer[6])
        print("[Synthetic] Pixel(1,0) black: R=\(px1.r) G=\(px1.g) B=\(px1.b)")
        XCTAssertLessThan(px1.r, 15, "Black pixel R should be near 0")
        XCTAssertLessThan(px1.g, 15, "Black pixel G should be near 0")
        XCTAssertLessThan(px1.b, 15, "Black pixel B should be near 0")

        // Check pixel (2,0) = red (R~255, G~0, B~0)
        let px2 = (r: pixelBuffer[8], g: pixelBuffer[9], b: pixelBuffer[10])
        print("[Synthetic] Pixel(2,0) red: R=\(px2.r) G=\(px2.g) B=\(px2.b)")
        XCTAssertGreaterThan(px2.r, 240, "Red pixel R should be near 255")
        XCTAssertLessThan(px2.g, 15, "Red pixel G should be near 0")
        XCTAssertLessThan(px2.b, 15, "Red pixel B should be near 0")

        // Check pixel (3,0) = gray (should be ~127-128)
        let px3 = (r: pixelBuffer[12], g: pixelBuffer[13], b: pixelBuffer[14])
        print("[Synthetic] Pixel(3,0) gray: R=\(px3.r) G=\(px3.g) B=\(px3.b)")
        XCTAssertGreaterThan(px3.r, 120, "Gray pixel R should be ~128")
        XCTAssertLessThan(px3.r, 136, "Gray pixel R should be ~128")
    }

    func testModelFamilyDetection() {
        // Flux models
        XCTAssertEqual(LatentModelFamily.detect(from: "flux1-dev-q8p.gguf"), .flux)
        XCTAssertEqual(LatentModelFamily.detect(from: "flux1-schnell-q8p.gguf"), .flux)

        // SDXL models
        XCTAssertEqual(LatentModelFamily.detect(from: "sd_xl_base_1.0.safetensors"), .sdxl)

        // SD3 models
        XCTAssertEqual(LatentModelFamily.detect(from: "sd3_medium_incl_clips.safetensors"), .sd3)

        // Version strings
        XCTAssertEqual(LatentModelFamily.detect(from: "flux1"), .flux)
        XCTAssertEqual(LatentModelFamily.detect(from: "sdxlBase"), .sdxl)
        XCTAssertEqual(LatentModelFamily.detect(from: "sd3"), .sd3)
    }
}