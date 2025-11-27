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
}