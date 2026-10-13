import Foundation

public struct PosterCrop: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var body: [String: JSONValue] {
        ["x": .number(Double(x)), "y": .number(Double(y)),
         "width": .number(Double(width)), "height": .number(Double(height))]
    }
}

// Keep the selection in source pixels so resizing the view does not change the crop.
public struct PosterCropSelection: Equatable, Sendable {
    public static let ratio = 2.0 / 3.0
    public let imageWidth: Int
    public let imageHeight: Int
    public private(set) var x: Double
    public private(set) var y: Double
    public private(set) var width: Double
    public var height: Double { width / Self.ratio }

    public init?(imageWidth: Int, imageHeight: Int) {
        guard imageWidth >= 2, imageHeight >= 3 else { return nil }
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        width = min(Double(imageWidth), Double(imageHeight) * Self.ratio)
        x = Double(imageWidth) - width
        y = 0
    }

    public func moved(dx: Double, dy: Double) -> Self {
        var result = self
        result.x = min(max(0, x + dx), Double(imageWidth) - width)
        result.y = min(max(0, y + dy), Double(imageHeight) - height)
        return result
    }

    public func resized(widthDelta: Double, minimumWidth: Double = 2) -> Self {
        var result = self
        let maximum = min(Double(imageWidth) - x, (Double(imageHeight) - y) * Self.ratio)
        result.width = min(max(width + widthDelta, min(max(2, minimumWidth), maximum)), maximum)
        return result
    }

    public var crop: PosterCrop {
        // Clamp after rounding as well: independently rounded edges can exceed the image.
        let left = min(max(0, Int(x.rounded())), imageWidth - 2)
        let top = min(max(0, Int(y.rounded())), imageHeight - 2)
        return PosterCrop(x: left, y: top,
                          width: min(max(2, Int(width.rounded())), imageWidth - left),
                          height: min(max(2, Int(height.rounded())), imageHeight - top))
    }
}
