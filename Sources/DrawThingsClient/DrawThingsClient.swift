//
//  DrawThingsClient.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import AVFoundation
import Foundation
import SwiftUI
import Combine

#if os(macOS)
import AppKit
#else
import UIKit
#endif

public struct GenerationOutput: Sendable {
    public let images: [PlatformImage]
    public let audio: [AVAudioPCMBuffer]
}

@MainActor
public class DrawThingsClient: ObservableObject {
    private let service: DrawThingsService
    
    @Published public var isConnected = false
    @Published public var currentProgress: ImageGenerationProgress?
    @Published public var lastError: Error?
    
    public init(address: String, useTLS: Bool = true) throws {
        self.service = try DrawThingsService(address: address, useTLS: useTLS)
    }
    
    public func connect() async {
        do {
            _ = try await service.echo()
            isConnected = true
            lastError = nil
        } catch {
            isConnected = false
            lastError = error
        }
    }
    
    public func generateImage(
        prompt: String,
        negativePrompt: String = "",
        configuration: DrawThingsConfiguration = DrawThingsConfiguration(),
        image: PlatformImage? = nil,
        mask: PlatformImage? = nil
    ) async throws -> [PlatformImage] {
        let result = try await performGeneration(
            prompt: prompt,
            negativePrompt: negativePrompt,
            configuration: configuration,
            image: image,
            mask: mask
        )
        return try result.images.map { try ImageHelpers.dtTensorToImage($0) }
    }

    public func generateImageAndAudio(
        prompt: String,
        negativePrompt: String = "",
        configuration: DrawThingsConfiguration = DrawThingsConfiguration(),
        image: PlatformImage? = nil,
        mask: PlatformImage? = nil
    ) async throws -> GenerationOutput {
        let result = try await performGeneration(
            prompt: prompt,
            negativePrompt: negativePrompt,
            configuration: configuration,
            image: image,
            mask: mask
        )

        let images = try result.images.map { try ImageHelpers.dtTensorToImage($0) }
        let audioBuffers = result.audio.compactMap { data in
            try? AudioHelpers.ccvTensorToAudioBuffer(data)
        }

        return GenerationOutput(images: images, audio: audioBuffers)
    }

    private func performGeneration(
        prompt: String,
        negativePrompt: String,
        configuration: DrawThingsConfiguration,
        image: PlatformImage?,
        mask: PlatformImage?
    ) async throws -> GenerationResult {
        currentProgress = ImageGenerationProgress()

        let configData = try configuration.toFlatBufferData()

        var imageData: Data?
        var maskData: Data?

        if let image = image {
            imageData = try ImageHelpers.imageToDTTensor(image, forceRGB: true)
        }

        if let mask = mask {
            maskData = try ImageHelpers.imageToDTTensor(mask, forceRGB: true)
        }

        let result = try await service.generateImage(
            prompt: prompt,
            negativePrompt: negativePrompt,
            configuration: configData,
            image: imageData,
            mask: maskData,
            progressHandler: { [weak self] signpost in
                await MainActor.run {
                    self?.updateProgress(signpost)
                }
            }
        )

        currentProgress = nil
        return result
    }
    
    private func updateProgress(_ signpost: ImageGenerationSignpostProto?) {
        guard let signpost = signpost else { return }
        
        switch signpost.signpost {
        case .textEncoded:
            currentProgress?.stage = .textEncoding
        case .imageEncoded:
            currentProgress?.stage = .imageEncoding
        case .sampling(let sampling):
            currentProgress?.stage = .sampling(step: Int(sampling.step))
        case .imageDecoded:
            currentProgress?.stage = .imageDecoding
        case .secondPassImageEncoded:
            currentProgress?.stage = .secondPassImageEncoding
        case .secondPassSampling(let sampling):
            currentProgress?.stage = .secondPassSampling(step: Int(sampling.step))
        case .secondPassImageDecoded:
            currentProgress?.stage = .secondPassImageDecoding
        case .faceRestored:
            currentProgress?.stage = .faceRestoration
        case .imageUpscaled:
            currentProgress?.stage = .imageUpscaling
        default:
            break
        }
    }
}

public class ImageGenerationProgress: ObservableObject {
    @Published public var stage: GenerationStage = .textEncoding
    
    public init() {}
}

public enum GenerationStage {
    case textEncoding
    case imageEncoding
    case sampling(step: Int)
    case imageDecoding
    case secondPassImageEncoding
    case secondPassSampling(step: Int)
    case secondPassImageDecoding
    case faceRestoration
    case imageUpscaling
    
    public var description: String {
        switch self {
        case .textEncoding:
            return "Encoding text prompt..."
        case .imageEncoding:
            return "Encoding input image..."
        case .sampling(let step):
            return "Generating image (step \(step))..."
        case .imageDecoding:
            return "Decoding generated image..."
        case .secondPassImageEncoding:
            return "Preparing second pass..."
        case .secondPassSampling(let step):
            return "Second pass generation (step \(step))..."
        case .secondPassImageDecoding:
            return "Processing second pass..."
        case .faceRestoration:
            return "Restoring faces..."
        case .imageUpscaling:
            return "Upscaling image..."
        }
    }
}
