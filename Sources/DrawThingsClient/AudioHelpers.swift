//
//  AudioHelpers.swift
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

public struct AudioHelpers {

    public enum AudioError: Error, CustomStringConvertible {
        case invalidData(String)
        case unsupportedDataType(UInt32)
        case bufferCreationFailed
        case fileWriteFailed

        public var description: String {
            switch self {
            case .invalidData(let detail):
                return "Audio tensor data invalid: \(detail)"
            case .unsupportedDataType(let type):
                return "Unsupported tensor data type: 0x\(String(type, radix: 16)). Expected CCV_32F (0x4000)."
            case .bufferCreationFailed:
                return "Failed to create AVAudioPCMBuffer"
            case .fileWriteFailed:
                return "Failed to write audio buffer to WAV file"
            }
        }
    }

    // CCV tensor data type constants
    private static let CCV_32F: UInt32 = 0x04000
    private static let CCV_16F: UInt32 = 0x20000

    // CCV tensor format flags
    private static let CCV_TENSOR_FORMAT_NCHW: UInt32 = 0x01
    private static let CCV_TENSOR_FORMAT_NHWC: UInt32 = 0x02


    /// Convert a CCV tensor (raw Float32 waveform) to an AVAudioPCMBuffer.
    ///
    /// The tensor is expected to have shape [channels, num_samples] (typically [2, n])
    /// with Float32 PCM data in [-1, 1] range.
    ///
    /// - Parameters:
    ///   - data: Raw CCV tensor bytes (68-byte header + Float32 sample data)
    ///   - sampleRate: Audio sample rate in Hz (default: 16000 for LTX-2)
    /// - Returns: An AVAudioPCMBuffer containing the decoded audio
    public static func ccvTensorToAudioBuffer(_ data: Data, sampleRate: Double = 16000) throws -> AVAudioPCMBuffer {
        guard data.count >= 68 else {
            throw AudioError.invalidData("data too small: \(data.count) bytes, need at least 68")
        }

        // Decompress if needed (handles deflate and fpzip compression)
        let data = try TensorDecompression.decompressIfNeeded(data)

        // Read 68-byte CCV tensor header (17 x UInt32)
        var header = [UInt32](repeating: 0, count: 17)
        data.prefix(68).withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let uint32Ptr = ptr.bindMemory(to: UInt32.self)
            for i in 0..<17 {
                header[i] = uint32Ptr[i]
            }
        }

        let formatFlag = header[2]
        let dataType = header[3]

        // Validate data type is Float32
        guard dataType == CCV_32F else {
            throw AudioError.unsupportedDataType(dataType)
        }

        // CCV tensor dimensions: header[5..16] = dim[0..11]
        // Audio tensors can be either:
        //   2D: dim[0]=channels, dim[1]=samples, dim[2]=0, dim[3]=0
        //   4D (image-like): dim[0]=1, dim[1]=height, dim[2]=width, dim[3]=channels
        let dim0 = Int(header[5])
        let dim1 = Int(header[6])
        let dim2 = Int(header[7])
        let dim3 = Int(header[8])

        let channels: Int
        let samplesPerChannel: Int

        if dim2 == 0 && dim3 == 0 {
            // 2D tensor: [channels, samples] (e.g., LTX audio: [2, 115440])
            channels = dim0
            samplesPerChannel = dim1
        } else if dim2 > 0 && dim3 > 0 {
            // 4D tensor: [N, height, width, channels]
            channels = dim3
            samplesPerChannel = dim1 * dim2
        } else {
            // 3D or other layout: try [channels, samples, 1]
            channels = dim0
            samplesPerChannel = dim1 * max(dim2, 1)
        }

        guard samplesPerChannel > 0 && channels > 0 else {
            throw AudioError.invalidData("invalid dimensions: channels=\(channels), samplesPerChannel=\(samplesPerChannel) (dims=[\(dim0), \(dim1), \(dim2), \(dim3)]), format=0x\(String(formatFlag, radix: 16))")
        }

        let totalFloats = channels * samplesPerChannel
        let pixelDataOffset = 68
        let expectedSize = pixelDataOffset + (totalFloats * MemoryLayout<Float>.size)

        guard data.count >= expectedSize else {
            throw AudioError.invalidData("data too small after header: \(data.count) bytes, expected \(expectedSize) (channels=\(channels), samples=\(samplesPerChannel))")
        }

        // Create audio format (non-interleaved Float32)
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(channels)
        ) else {
            throw AudioError.bufferCreationFailed
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samplesPerChannel)
        ) else {
            throw AudioError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(samplesPerChannel)

        guard let floatChannelData = buffer.floatChannelData else {
            throw AudioError.bufferCreationFailed
        }

        // Copy Float32 data from tensor to buffer
        data.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
            let floatPtr = rawPtr.baseAddress!.advanced(by: pixelDataOffset)
                .assumingMemoryBound(to: Float.self)

            let isNHWC = (formatFlag & CCV_TENSOR_FORMAT_NHWC) != 0

            if isNHWC {
                // Interleaved: [s0_ch0, s0_ch1, s1_ch0, s1_ch1, ...]
                for sample in 0..<samplesPerChannel {
                    for ch in 0..<channels {
                        floatChannelData[ch][sample] = floatPtr[sample * channels + ch]
                    }
                }
            } else {
                // NCHW / planar: [ch0_s0, ch0_s1, ..., ch1_s0, ch1_s1, ...]
                // This matches AVAudioPCMBuffer's non-interleaved layout perfectly
                for ch in 0..<channels {
                    let srcOffset = ch * samplesPerChannel
                    memcpy(floatChannelData[ch], floatPtr.advanced(by: srcOffset),
                           samplesPerChannel * MemoryLayout<Float>.size)
                }
            }
        }

        return buffer
    }

    /// Convert an AVAudioPCMBuffer to WAV file data.
    ///
    /// - Parameter buffer: The audio buffer to convert
    /// - Returns: WAV file data that can be written to disk
    public static func audioBufferToWAVData(_ buffer: AVAudioPCMBuffer) throws -> Data {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            let file = try AVAudioFile(
                forWriting: tempURL,
                settings: buffer.format.settings
            )
            try file.write(from: buffer)
        } catch {
            throw AudioError.fileWriteFailed
        }

        do {
            return try Data(contentsOf: tempURL)
        } catch {
            throw AudioError.fileWriteFailed
        }
    }
}
