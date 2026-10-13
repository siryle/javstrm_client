import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.dropFirst().first ?? "JavStrm/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 40.0 / 255, green: 101.0 / 255, blue: 82.0 / 255, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Reproduce JavStrm's existing vector brand mark at app-icon resolution.
func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * 16, y: (64 - y) * 16) }
let mark = CGMutablePath()
mark.move(to: point(29, 15))
for p in [(49.0, 15.0), (49, 22), (43, 22), (43, 41)] { mark.addLine(to: point(p.0, p.1)) }
mark.addCurve(to: point(28, 56), control1: point(43, 51), control2: point(37, 56))
mark.addCurve(to: point(15, 43), control1: point(20, 56), control2: point(15, 51))
mark.addLine(to: point(23, 43))
mark.addCurve(to: point(28, 49), control1: point(23, 47), control2: point(25, 49))
mark.addCurve(to: point(35, 41), control1: point(33, 49), control2: point(35, 46))
mark.addLine(to: point(35, 22))
mark.addLine(to: point(29, 22))
mark.closeSubpath()
context.setFillColor(CGColor(red: 245.0 / 255, green: 244.0 / 255, blue: 239.0 / 255, alpha: 1))
context.addPath(mark)
context.fillPath()
let play = CGMutablePath()
play.move(to: point(16, 17))
play.addLine(to: point(28, 25))
play.addLine(to: point(16, 33))
play.closeSubpath()
context.setFillColor(CGColor(red: 223.0 / 255, green: 175.0 / 255, blue: 136.0 / 255, alpha: 1))
context.addPath(play)
context.fillPath()
try FileManager.default.createDirectory(at: URL(fileURLWithPath: output).deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination), "Could not write app icon")
print("Generated \(output)")
