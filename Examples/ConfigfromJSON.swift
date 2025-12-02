//
//  Config from JSON.swift
//  DrawThingsClient
//  These functions are for creating a DrawThingsConfiguration from JSON provided in a String

/// Load configuration from JSON, applying only values that are present in the JSON
/// All other values use DrawThingsConfiguration defaults
private func loadDrawThingsConfig(for key: String) async -> DrawThingsConfiguration? {
    // Load JSON string from UserDefaults (saved by SettingsView)
    guard let jsonString = UserDefaults.standard.string(forKey: key) else {
        print("⚠️ No config found for key: \(key)")
        return nil
    }
    
    print("📄 Loaded JSON config (\(jsonString.count) characters)")
    
    // Parse as generic JSON to extract fields
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("❌ Failed to parse JSON")
        return nil
    }
    
    // Extract core fields (with fallbacks)
    let model = json["model"] as? String ?? ""
    let steps = json["steps"] as? Int ?? 30
    let width = json["width"] as? Int ?? 1152
    let height = json["height"] as? Int ?? 1728
    
    // IMPORTANT: Validate model is not empty to prevent crash
    guard !model.isEmpty else {
        print("❌ Model name is empty in configuration!")
        return nil
    }
    
    // Sampler handling - convert from int to SamplerType enum
    var samplerType: SamplerType = .dpmpp2mkarras
    if let samplerInt = json["sampler"] as? Int {
        samplerType = mapSamplerIntToEnum(samplerInt)
    }
    
    // Text Guidance - guidanceScale in JSON
    let cfgScale = (json["guidanceScale"] as? Double) ?? 7.0
    
    // Parse LoRAs
    var loras: [LoRAConfig] = []
    if let lorasArray = json["loras"] as? [[String: Any]] {
        for loraDict in lorasArray {
            if let file = loraDict["file"] as? String {
                let weight = Float(loraDict["weight"] as? Double ?? 1.0)
                let modeInt = loraDict["mode"] as? Int ?? 0
                let mode = mapLoRAModeIntToEnum(modeInt)
                loras.append(LoRAConfig(file: file, weight: weight, mode: mode))
            }
        }
    }
    
    // Parse Controls
    var controls: [ControlConfig] = []
    if let controlsArray = json["controls"] as? [[String: Any]] {
        for controlDict in controlsArray {
            if let file = controlDict["file"] as? String {
                let weight = Float(controlDict["weight"] as? Double ?? 1.0)
                let guidanceStart = Float(controlDict["guidanceStart"] as? Double ?? 0.0)
                let guidanceEnd = Float(controlDict["guidanceEnd"] as? Double ?? 1.0)
                let controlModeInt = controlDict["controlImportance"] as? Int ?? 0
                let controlMode = mapControlModeIntToEnum(controlModeInt)
                controls.append(ControlConfig(
                    file: file,
                    weight: weight,
                    guidanceStart: guidanceStart,
                    guidanceEnd: guidanceEnd,
                    controlMode: controlMode
                ))
            }
        }
    }
    
    // Strength handling - use value from JSON config
    let strength = Float(json["strength"] as? Double ?? 1.0)
    
    // Extract ALL other parameters with defaults
    let shift = Float(json["shift"] as? Double ?? 1.0)
    let clipSkip = Int32(json["clipSkip"] as? Int ?? 1)
    
    // Batch parameters
    let batchCount = Int32(json["batchCount"] as? Int ?? 1)
    let batchSize = Int32(json["batchSize"] as? Int ?? 1)
    
    // Guidance parameters
    let imageGuidanceScale = Float(json["imageGuidanceScale"] as? Double ?? 1.5)
    let clipWeight = Float(json["clipWeight"] as? Double ?? 1.0)
    let guidanceEmbed = Float(json["guidanceEmbed"] as? Double ?? cfgScale)
    let speedUpWithGuidanceEmbed = json["speedUpWithGuidanceEmbed"] as? Bool ?? true
    let cfgZeroStar = json["cfgZeroStar"] as? Bool ?? false
    let cfgZeroInitSteps = Int32(json["cfgZeroInitSteps"] as? Int ?? 0)

    // Mask/Inpaint parameters
    let maskBlur = Float(json["maskBlur"] as? Double ?? 1.5)
    let maskBlurOutset = Int32(json["maskBlurOutset"] as? Int ?? 0)
    let preserveOriginalAfterInpaint = json["preserveOriginalAfterInpaint"] as? Bool ?? true
    let enableInpainting = json["enableInpainting"] as? Bool ?? false
    
    // Quality parameters
    let sharpness = Float(json["sharpness"] as? Double ?? 0.0)
    let stochasticSamplingGamma = Float(json["stochasticSamplingGamma"] as? Double ?? 0.3)
    let aestheticScore = Float(json["aestheticScore"] as? Double ?? 6.0)
    let negativeAestheticScore = Float(json["negativeAestheticScore"] as? Double ?? 2.5)
    
    // Image prior parameters
    let negativePromptForImagePrior = json["negativePromptForImagePrior"] as? Bool ?? true
    let imagePriorSteps = Int32(json["imagePriorSteps"] as? Int ?? 5)
    
    // Crop/Size parameters
    let cropTop = Int32(json["cropTop"] as? Int ?? 0)
    let cropLeft = Int32(json["cropLeft"] as? Int ?? 0)
    let originalImageHeight = Int32(json["originalImageHeight"] as? Int ?? 0)
    let originalImageWidth = Int32(json["originalImageWidth"] as? Int ?? 0)
    let targetImageHeight = Int32(json["targetImageHeight"] as? Int ?? 0)
    let targetImageWidth = Int32(json["targetImageWidth"] as? Int ?? 0)
    let negativeOriginalImageHeight = Int32(json["negativeOriginalImageHeight"] as? Int ?? 0)
    let negativeOriginalImageWidth = Int32(json["negativeOriginalImageWidth"] as? Int ?? 0)
    
    // Upscaler parameters
    let upscalerScaleFactor = Int32(json["upscalerScaleFactor"] as? Int ?? 0)
    
    // Text encoder parameters
    let resolutionDependentShift = json["resolutionDependentShift"] as? Bool ?? true
    let t5TextEncoder = json["t5TextEncoder"] as? Bool ?? true
    let separateClipL = json["separateClipL"] as? Bool ?? false
    let separateOpenClipG = json["separateOpenClipG"] as? Bool ?? false
    let separateT5 = json["separateT5"] as? Bool ?? false
    
    // Tiled parameters
    let tiledDiffusion = json["tiledDiffusion"] as? Bool ?? false
    let diffusionTileWidth = Int32(json["diffusionTileWidth"] as? Int ?? 16)
    let diffusionTileHeight = Int32(json["diffusionTileHeight"] as? Int ?? 16)
    let diffusionTileOverlap = Int32(json["diffusionTileOverlap"] as? Int ?? 2)
    let tiledDecoding = json["tiledDecoding"] as? Bool ?? false
    let decodingTileWidth = Int32(json["decodingTileWidth"] as? Int ?? 10)
    let decodingTileHeight = Int32(json["decodingTileHeight"] as? Int ?? 10)
    let decodingTileOverlap = Int32(json["decodingTileOverlap"] as? Int ?? 2)
    
    // HiRes Fix parameters
    let hiresFix = json["hiresFix"] as? Bool ?? false
    let hiresFixWidth = Int32(json["hiresFixWidth"] as? Int ?? 0)
    let hiresFixHeight = Int32(json["hiresFixHeight"] as? Int ?? 0)
    let hiresFixStrength = Float(json["hiresFixStrength"] as? Double ?? 0.7)
    
    // Stage 2 parameters
    let stage2Steps = Int32(json["stage2Steps"] as? Int ?? 10)
    let stage2Guidance = Float(json["stage2Guidance"] as? Double ?? 1.0)
    let stage2Shift = Float(json["stage2Shift"] as? Double ?? 1.0)
    
    // TEA Cache parameters
    let teaCache = json["teaCache"] as? Bool ?? false
    let teaCacheStart = Int32(json["teaCacheStart"] as? Int ?? 5)
    let teaCacheEnd = Int32(json["teaCacheEnd"] as? Int ?? -1)
    let teaCacheThreshold = Float(json["teaCacheThreshold"] as? Double ?? 0.06)
    let teaCacheMaxSkipSteps = Int32(json["teaCacheMaxSkipSteps"] as? Int ?? 3)
    
    // Causal inference parameters
    let causalInference = Int32(json["causalInference"] as? Int ?? 0)
    let causalInferencePad = Int32(json["causalInferencePad"] as? Int ?? 0)
    
    // Video parameters
    let fps = Int32(json["fps"] as? Int ?? 5)
    let motionScale = Int32(json["motionScale"] as? Int ?? 127)
    let guidingFrameNoise = Float(json["guidingFrameNoise"] as? Double ?? 0.02)
    let startFrameGuidance = Float(json["startFrameGuidance"] as? Double ?? 1.0)
    let numFrames = Int32(json["numFrames"] as? Int ?? 14)
    
    // Refiner parameters
    let refinerModel = json["refinerModel"] as? String
    let refinerStart = Float(json["refinerStart"] as? Double ?? 0.85)
    let zeroNegativePrompt = json["zeroNegativePrompt"] as? Bool ?? false
    
    // Seed mode
    let seedMode = Int32(json["seedMode"] as? Int ?? 2)
    
    print("✅ Parsed config:")
    print("   Model: \(model)")
    print("   Steps: \(steps), CFG: \(cfgScale), Size: \(width)x\(height)")
    print("   Sampler: \(samplerType) (rawValue: \(samplerType.rawValue)), Shift: \(shift), Strength: \(strength)")
    print("   LoRAs: \(loras.count), Controls: \(controls.count)")
    
    // Create DrawThingsConfiguration with ALL parameters
    let config = DrawThingsConfiguration(
        width: Int32(width),
        height: Int32(height),
        steps: Int32(steps),
        model: model,
        sampler: samplerType,
        guidanceScale: Float(cfgScale),
        seed: nil,
        clipSkip: clipSkip,
        loras: loras,
        controls: controls,
        shift: shift,
        batchCount: batchCount,
        batchSize: batchSize,
        strength: strength,
        imageGuidanceScale: imageGuidanceScale,
        clipWeight: clipWeight,
        guidanceEmbed: guidanceEmbed,
        speedUpWithGuidanceEmbed: speedUpWithGuidanceEmbed,
        cfgZeroStar: cfgZeroStar,
        cfgZeroInitSteps: cfgZeroInitSteps,
        maskBlur: maskBlur,
        maskBlurOutset: maskBlurOutset,
        preserveOriginalAfterInpaint: preserveOriginalAfterInpaint,
        enableInpainting: enableInpainting,
        sharpness: sharpness,
        stochasticSamplingGamma: stochasticSamplingGamma,
        aestheticScore: aestheticScore,
        negativeAestheticScore: negativeAestheticScore,
        negativePromptForImagePrior: negativePromptForImagePrior,
        imagePriorSteps: imagePriorSteps,
        cropTop: cropTop,
        cropLeft: cropLeft,
        originalImageHeight: originalImageHeight,
        originalImageWidth: originalImageWidth,
        targetImageHeight: targetImageHeight,
        targetImageWidth: targetImageWidth,
        negativeOriginalImageHeight: negativeOriginalImageHeight,
        negativeOriginalImageWidth: negativeOriginalImageWidth,
        upscalerScaleFactor: upscalerScaleFactor,
        resolutionDependentShift: resolutionDependentShift,
        t5TextEncoder: t5TextEncoder,
        separateClipL: separateClipL,
        separateOpenClipG: separateOpenClipG,
        separateT5: separateT5,
        tiledDiffusion: tiledDiffusion,
        diffusionTileWidth: diffusionTileWidth,
        diffusionTileHeight: diffusionTileHeight,
        diffusionTileOverlap: diffusionTileOverlap,
        tiledDecoding: tiledDecoding,
        decodingTileWidth: decodingTileWidth,
        decodingTileHeight: decodingTileHeight,
        decodingTileOverlap: decodingTileOverlap,
        hiresFix: hiresFix,
        hiresFixWidth: hiresFixWidth,
        hiresFixHeight: hiresFixHeight,
        hiresFixStrength: hiresFixStrength,
        stage2Steps: stage2Steps,
        stage2Guidance: stage2Guidance,
        stage2Shift: stage2Shift,
        teaCache: teaCache,
        teaCacheStart: teaCacheStart,
        teaCacheEnd: teaCacheEnd,
        teaCacheThreshold: teaCacheThreshold,
        teaCacheMaxSkipSteps: teaCacheMaxSkipSteps,
        causalInference: causalInference,
        causalInferencePad: causalInferencePad,
        fps: fps,
        motionScale: motionScale,
        guidingFrameNoise: guidingFrameNoise,
        startFrameGuidance: startFrameGuidance,
        numFrames: numFrames,
        refinerModel: refinerModel,
        refinerStart: refinerStart,
        zeroNegativePrompt: zeroNegativePrompt,
        seedMode: seedMode
    )
    
    return config
}

/// Map DrawThings sampler integer to SamplerType enum
/// Based on SamplerType enum from DrawThings FlatBuffers schema
private func mapSamplerIntToEnum(_ samplerInt: Int) -> SamplerType {
    switch samplerInt {
    case 0: return .dpmpp2mkarras
    case 1: return .eulera
    case 2: return .ddim
    case 3: return .plms
    case 4: return .dpmppsdekarras
    case 5: return .unipc
    case 6: return .lcm
    case 7: return .eulerasubstep
    case 8: return .dpmppsdesubstep
    case 9: return .tcd
    case 10: return .euleratrailing
    case 11: return .dpmppsdetrailing
    case 12: return .dpmpp2mays
    case 13: return .euleraays
    case 14: return .dpmppsdeays
    case 15: return .dpmpp2mtrailing
    case 16: return .ddimtrailing
    case 17: return .unipctrailing
    case 18: return .unipcays
    default: return .dpmpp2mkarras  // Default to case 0
    }
}

/// Map DrawThings LoRA mode integer to LoRAMode enum
/// Based on LoRAMode enum from DrawThings FlatBuffers schema
private func mapLoRAModeIntToEnum(_ modeInt: Int) -> LoRAMode {
    switch modeInt {
    case 0: return .all
    case 1: return .base
    case 2: return .refiner
    default: return .all  // Default to case 0
    }
}

/// Map DrawThings control mode integer to ControlMode enum
/// Based on ControlMode enum from DrawThings FlatBuffers schema
private func mapControlModeIntToEnum(_ modeInt: Int) -> ControlMode {
    switch modeInt {
    case 0: return .balanced
    case 1: return .prompt
    case 2: return .control
    default: return .balanced  // Default to case 0
    }
}
