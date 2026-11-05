import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import Tidemeld

struct ImageLoaderTests {
    /// A GIF of [frames] frames, [side] pixels square.
    private func gif(frames: Int, side: Int) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames, nil)!
        let frame = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side / 2, height: side / 2))
        }
        let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
        for _ in 0..<frames { CGImageDestinationAddImage(destination, frame.cgImage!, properties) }
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test func animatedPicturesShrinkToFitTheirMemory() throws {
        let image = try #require(ImageLoader.decode(gif(frames: 50, side: 800), maxPixels: 600))

        let frames = try #require(image.images)
        #expect(frames.count == 50)
        let side = ImageLoader.animatedSide(CGSize(width: 800, height: 800), frames: 50, maxPixels: 600)
        #expect(side < 600)
        #expect(frames[0].size.width * frames[0].scale <= side)
        // 16 MB at most, as a list holds it.
        let bytes = frames.reduce(0) { $0 + $1.size.width * $1.scale * $1.size.height * $1.scale * 4 }
        #expect(bytes <= 16 * 1024 * 1024)
    }

    @Test func shortAnimationsKeepTheSizeAsked() throws {
        let image = try #require(ImageLoader.decode(gif(frames: 3, side: 400), maxPixels: 300))

        let frames = try #require(image.images)
        #expect(frames[0].size.width * frames[0].scale == 300)
    }
}
