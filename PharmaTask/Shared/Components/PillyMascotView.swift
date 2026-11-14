import SwiftUI

/// Kept for existing call sites; all branding now uses the same scalable asset.
public struct PillyMascotView: View {
    var size: CGFloat
    public init(size: CGFloat = 36) { self.size = size }
    public var body: some View { HopeBrandMark(size: size) }
}
