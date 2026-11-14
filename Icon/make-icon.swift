// Turns the logo artwork, Icon/source.png, into:
//   Icon/AppIcon.icns  the app icon, in every size macOS wants
// Run from the project folder:  swift Icon/make-icon.swift
import AppKit

func canvas(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ image: CGImage, _ path: String) {
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
}

/// Draw `art` as large as fits in a `fit`×`fit` square, centered on a `size`×`size` transparent canvas.
func place(_ art: CGImage, fit: CGFloat, size: Int) -> CGImage {
    let context = canvas(size, size)
    context.interpolationQuality = .high
    let scale = fit / CGFloat(max(art.width, art.height))
    let width = CGFloat(art.width) * scale
    let height = CGFloat(art.height) * scale
    context.draw(art, in: CGRect(x: (CGFloat(size) - width) / 2, y: (CGFloat(size) - height) / 2,
                                 width: width, height: height))
    return context.makeImage()!
}

let source = NSImage(contentsOfFile: "Icon/source.png")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let width = source.width
let height = source.height

// 1. Find the artwork: the rows and columns with more than 50 solid pixels.
//    Specks of dust around it are too small to count, so cropping drops them.
let reader = canvas(width, height)
reader.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = reader.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
func solid(_ x: Int, _ y: Int) -> Bool { pixels[(y * width + x) * 4 + 3] > 128 }   // byte 3 is alpha

let rows = (0..<height).filter { y in (0..<width).count { solid($0, y) } > 50 }
let columns = (0..<width).filter { x in (0..<height).count { solid(x, $0) } > 50 }
let art = source.cropping(to: CGRect(x: columns.first!, y: rows.first!,
                                     width: columns.last! - columns.first! + 1,
                                     height: rows.last! - rows.first! + 1))!

// 2. App icon. On macOS's 1024 grid the tile fills the middle 824×824, leaving room for the shadow.
let folder = "Icon/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: folder)
try! FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        save(place(art, fit: CGFloat(size) * 824 / 1024, size: size), "\(folder)/\(name)")
    }
}
let pack = Process()
pack.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
pack.arguments = ["-c", "icns", folder, "-o", "Icon/AppIcon.icns"]
try! pack.run()
pack.waitUntilExit()
try? FileManager.default.removeItem(atPath: folder)
print("Wrote Icon/AppIcon.icns")
