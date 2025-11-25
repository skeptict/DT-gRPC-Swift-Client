<p align="center">
  <img src="Assets/logo.png" alt="DrawThingsKit Logo" width="200"/>
</p>

# DrawThingsKit

A Swift framework for interacting with Draw Things gRPC server, designed for easy integration with SwiftUI applications on macOS.

## Features

- **Modern Swift Concurrency**: Built with async/await for clean, readable asynchronous code
- **SwiftUI Integration**: ObservableObject-based client with @Published properties for reactive UI updates
- **Progress Tracking**: Real-time progress updates during image generation
- **Image Utilities**: Built-in helpers for image conversion and manipulation
- **Type Safety**: Full Swift type safety with generated protobuf code

## Feature Status

### ✅ Tested & Working

The following features have been tested and confirmed working:

- **Text-to-Image Generation**: Basic image generation from text prompts
- **Image-to-Image**: Transform existing images based on prompts
- **Inpainting**: Selective image editing with masks
- **Moodboard/Reference Images**: Using reference images to influence generation (shuffle hints)
- **Progress Tracking**: Real-time generation progress updates
- **Preview Images**: Receive preview images during generation
- **Model Metadata**: Query available models and samplers

### ⚠️ Untested Features

The following features are available in the protocol but have not yet been tested:

- **ControlNet Support**: Using ControlNet models for guided generation
- **Video Generation**: Generating video/animation sequences
- **Multi-stage Models**: Stage 2 parameters for multi-stage generation pipelines
- **Advanced Optimization**: TEA Cache and other performance optimizations
- **File Upload**: Uploading models or other files to the server

Contributions and testing reports for these features are welcome!

## Requirements

- macOS 14.0+
- iOS 17.0+ (if building for iOS)
- Xcode 15.0+
- Swift 5.9+
- Draw Things app with gRPC server enabled or standalone gRPC server for nVidia

### Draw Things Server Setup

To use this framework, you need to configure the Draw Things gRPC server with the following settings:

1. **Response Compression**: Must be **disabled**
   - Having server-side compression enabled will cause failure, the framework does not currently have the ability to decompress responses

2. **Enable Model Browsing**: Recommended to be **enabled**
   - This allows the framework to query available models, samplers, and other metadata
   - Required for proper initialization and model selection

## Installation

### Swift Package Manager

Add DrawThingsKit to your project via Xcode:

1. File → Add Package Dependencies...
2. Enter the repository URL
3. Select the version/branch you want to use

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client", from: "1.0.0")
]
```

## Quick Start

### Basic Usage

```swift
import DrawThingsKit
import SwiftUI

struct ContentView: View {
    @StateObject private var client: DrawThingsClient
    @State private var prompt = "A beautiful landscape"
    
    init() {
        do {
            let client = try DrawThingsClient(address: "localhost:7859")
            _client = StateObject(wrappedValue: client)
        } catch {
            fatalError("Failed to create client: \(error)")
        }
    }
    
    var body: some View {
        VStack {
            TextField("Enter prompt", text: $prompt)
            
            Button("Generate") {
                Task {
                    await generateImage()
                }
            }
            .disabled(!client.isConnected)
            
            if let progress = client.currentProgress {
                Text(progress.stage.description)
                ProgressView()
            }
        }
        .task {
            await client.connect()
        }
    }
    
    private func generateImage() async {
        do {
            let config = DrawThingsConfiguration(
                width: 512,
                height: 512,
                steps: 20
            )
            
            let images = try await client.generateImage(
                prompt: prompt,
                configuration: config
            )
            
            // Use generated images...
        } catch {
            print("Generation failed: \(error)")
        }
    }
}
```

### Configuration Options

```swift
let config = DrawThingsConfiguration(
    width: 1024,
    height: 1024,
    steps: 30,
    model: "sd_xl_base_1.0.safetensors",
    sampler: SamplerType.dpm2a.rawValue,
    cfgScale: 7.5,
    seed: 12345,
    clipSkip: 2
)
```

### Image-to-Image Generation

```swift
let inputImage = NSImage(named: "input.jpg")!

let images = try await client.generateImage(
    prompt: "Transform this into a watercolor painting",
    configuration: config,
    image: inputImage
)
```

### Inpainting with Mask

```swift
let inputImage = NSImage(named: "photo.jpg")!
let maskImage = NSImage(named: "mask.png")!

let images = try await client.generateImage(
    prompt: "A cat sitting in the masked area",
    configuration: config,
    image: inputImage,
    mask: maskImage
)
```

### Moodboard / Reference Images

Use moodboard (also known as "shuffle") to provide reference images that influence the generation. This is particularly useful with models like Qwen Image Edit:

```swift
// Single reference image
let referenceImage = NSImage(named: "style_reference.jpg")!
let referenceData = try ImageHelpers.nsImageToDTTensor(referenceImage, forceRGB: true)

var tensorAndWeight = TensorAndWeight()
tensorAndWeight.tensor = referenceData
tensorAndWeight.weight = 1.0  // Weight from 0.0 to 1.0

var hint = HintProto()
hint.hintType = "shuffle"  // Use "shuffle" for moodboard/reference images
hint.tensors = [tensorAndWeight]

let images = try await service.generateImage(
    prompt: "A woman wearing a blue dress",
    negativePrompt: "",
    configuration: configData,
    hints: [hint]
)
```

Multiple reference images can be provided by adding more hints to the array:

```swift
// Multiple reference images
var hints: [HintProto] = []

let referenceImages = [
    NSImage(named: "dress_ref.jpg")!,
    NSImage(named: "style_ref.jpg")!,
    NSImage(named: "color_ref.jpg")!
]

for refImage in referenceImages {
    let imageData = try ImageHelpers.nsImageToDTTensor(refImage, forceRGB: true)

    var tensorAndWeight = TensorAndWeight()
    tensorAndWeight.tensor = imageData
    tensorAndWeight.weight = 1.0

    var hint = HintProto()
    hint.hintType = "shuffle"
    hint.tensors = [tensorAndWeight]

    hints.append(hint)
}

let images = try await service.generateImage(
    prompt: "Combine elements from the reference images",
    negativePrompt: "",
    configuration: configData,
    hints: hints
)
```

**Note:** The moodboard feature works best with models that are designed to use reference images.

## Architecture

DrawThingsKit is built on top of:

- **gRPC Swift 2**: Modern gRPC client with async/await support
- **SwiftProtobuf**: Type-safe protocol buffer implementation
- **SwiftNIO**: High-performance networking

The framework provides two main interfaces:

1. **DrawThingsService**: Low-level async actor for direct gRPC communication
2. **DrawThingsClient**: High-level ObservableObject for SwiftUI integration

## Development

### Building from Source

1. Clone the repository
2. Install dependencies:
   ```bash
   brew install protoc-gen-grpc-swift swift-protobuf
   ```
3. Generate protobuf code (if needed):
   ```bash
   ./generate_protos.sh
   ```
4. Build:
   ```bash
   swift build
   ```

### Running Tests

```bash
swift test
```

### Example App

The repository includes a complete SwiftUI example application:

```bash
cd Examples/SwiftUIExample
swift run
```

## API Reference

### DrawThingsClient (SwiftUI)

- `init(address: String, useTLS: Bool = true)`: Create a new client
- `connect() async`: Connect to the Draw Things server
- `generateImage(...)` async: Generate images with progress tracking
- `@Published var isConnected`: Connection status
- `@Published var currentProgress`: Current generation progress

### DrawThingsService (Low-level)

- `echo(name:) async throws -> EchoReply`: Server health check
- `generateImage(...) async throws -> [Data]`: Generate images
- `checkFilesExist(...) async throws -> FileExistenceResponse`: Check file existence

### Configuration

- `DrawThingsConfiguration`: Image generation parameters
- `SamplerType`: Available sampling methods
- `ImageHelpers`: Image conversion utilities

## Error Handling

```swift
do {
    let images = try await client.generateImage(prompt: "test")
} catch DrawThingsError.connectionFailed {
    // Handle connection issues
} catch DrawThingsError.generationFailed(let reason) {
    // Handle generation errors
} catch {
    // Handle other errors
}
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Compatibility

This framework is converted from the original TypeScript implementation and maintains API compatibility with the Draw Things gRPC server protocol.
