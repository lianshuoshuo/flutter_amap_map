import Flutter
import UIKit
import MAMapKit
import ImageIO

final class BridgeMarker: MAPointAnnotation {
    let markerId: String
    let image: UIImage
    let pngData: Data
    let offset: CGPoint
    let angle: CGFloat
    let order: Int
    let visible: Bool
    init(_ data: [String: Any], previous: BridgeMarker?) throws {
        func number(_ key: String, _ range: ClosedRange<Double>) throws -> Double {
            guard let n = data[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue.isFinite, range.contains(n.doubleValue) else { throw MarkerInputError.invalid }
            return n.doubleValue
        }
        guard let id = data["id"] as? String, !id.isEmpty,
              let bytes = data["pngBytes"] as? FlutterStandardTypedData,
              (8...4194304).contains(bytes.data.count),
              Array(bytes.data.prefix(8)) == [137,80,78,71,13,10,26,10],
              let source = CGImageSourceCreateWithData(bytes.data as CFData, nil),
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = info[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = info[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(pixelWidth), (1...4096).contains(pixelHeight),
              let original = UIImage(data: bytes.data), let visible = data["visible"] as? Bool
        else { throw MarkerInputError.invalid }
        let lat = try number("latitude", -90...90), lng = try number("longitude", -180...180)
        let width = try number("width", 0.000001...512), height = try number("height", 0.000001...512)
        let u = try number("anchorU", 0...1), v = try number("anchorV", 0...1)
        let degrees = try number("rotation", 0...360)
        guard degrees < 360 else { throw MarkerInputError.invalid }
        let angle = degrees * .pi / 180
        let z = try number("zIndex", -1000000...1000000)
        guard z.rounded() == z else { throw MarkerInputError.invalid }
        markerId = id
        pngData = bytes.data
        if let previous = previous, previous.pngData == bytes.data, previous.image.size == CGSize(width: width, height: height) {
            image = previous.image
        } else {
            image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { _ in
                original.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        let x = (0.5 - u) * width, y = (0.5 - v) * height
        offset = CGPoint(x: x * cos(angle) - y * sin(angle), y: x * sin(angle) + y * cos(angle))
        self.angle = CGFloat(angle)
        order = Int(z)
        self.visible = visible
        super.init()
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

enum MarkerInputError: Error { case invalid }

final class MarkerStore {
    private(set) var entries: [String: BridgeMarker] = [:]
    func apply(_ map: MAMapView, args: Any?) throws {
        guard let args = args as? [String: Any], let upsert = args["upsert"] as? [[String: Any]],
              let remove = args["remove"] as? [String] else { throw MarkerInputError.invalid }
        var prepared: [String: BridgeMarker] = [:]
        for data in upsert {
            let marker = try BridgeMarker(data, previous: entries[data["id"] as? String ?? ""])
            guard prepared[marker.markerId] == nil, !remove.contains(marker.markerId) else { throw MarkerInputError.invalid }
            prepared[marker.markerId] = marker
        }
        for (id, marker) in prepared {
            if let old = entries.removeValue(forKey: id) { map.removeAnnotation(old) }
            entries[id] = marker
            map.addAnnotation(marker)
        }
        for id in remove {
            if let old = entries.removeValue(forKey: id) { map.removeAnnotation(old) }
        }
    }
    func clear(_ map: MAMapView?) {
        map?.removeAnnotations(Array(entries.values))
        entries.removeAll()
    }
}
