import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Strips the alpha channel from the App Store icon (Apple rejects icons with alpha).
// Usage: swift flatten_icon.swift <input.png> <output.png>
let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift flatten_icon.swift in.png out.png\n".utf8))
    exit(2)
}

let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("cannot read \(input.path)\n".utf8))
    exit(1)
}

let width = image.width
let height = image.height
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(data: nil,
                              width: width,
                              height: height,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    FileHandle.standardError.write(Data("cannot create RGB context\n".utf8))
    exit(1)
}

// Paint the background white first so any transparent pixels don't turn black.
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

guard let flattened = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("cannot create destination\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, flattened, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("cannot write \(output.path)\n".utf8))
    exit(1)
}
print("wrote \(output.path) (\(width)x\(height), no alpha)")
