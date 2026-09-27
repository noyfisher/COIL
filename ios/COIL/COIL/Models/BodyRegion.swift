import Foundation
import CoreGraphics

enum BodySide: String, Codable, CaseIterable {
    case front
    case back
}

struct BodyRegion: Identifiable, Codable {
    let id: UUID
    let name: String
    let zoneKey: String
    let sides: [BodySide]
    let frontPosition: CGPoint?
    let backPosition: CGPoint?
    var isSelected: Bool

    init(name: String, zoneKey: String, sides: [BodySide], frontPosition: CGPoint?, backPosition: CGPoint?) {
        self.id = UUID()
        self.name = name
        self.zoneKey = zoneKey
        self.sides = sides
        self.frontPosition = frontPosition
        self.backPosition = backPosition
        self.isSelected = false
    }

    /// Returns the position for the given body side, or nil if not visible on that side.
    func position(for side: BodySide) -> CGPoint? {
        switch side {
        case .front: return frontPosition
        case .back: return backPosition
        }
    }
}
