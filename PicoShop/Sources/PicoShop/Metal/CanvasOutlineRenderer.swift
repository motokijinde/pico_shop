import SwiftUI
import MetalKit

extension CanvasRenderer {
    static func rectPolyline(_ rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY),
        ]
    }

    func activeOutlineTransform(model: AppModel, rect: CGRect) -> OverlayScene.Transform2D {
        let activeTransform = model.dragPreviewTransform ?? model.pendingTransform
        var affine = model.canvasToViewAffine
        if !activeTransform.isIdentity {
            affine = activeTransform
                .affine(center: CGPoint(x: rect.midX, y: rect.midY))
                .concatenating(affine)
        }
        return OverlayScene.Transform2D(affine: affine)
    }

    func appendAlternatingDashedOutline(_ scene: inout OverlayScene, mesh: StrokeMesh,
                                        transform: OverlayScene.Transform2D,
                                        width: CGFloat = 1,
                                        dashOn: CGFloat = 5,
                                        dashOff: CGFloat = 5,
                                        phaseModulo: CGFloat = 10) {
        let phase = CGFloat(CACurrentMediaTime() * 20).truncatingRemainder(dividingBy: phaseModulo)
        scene.items.append(.strokeCached(mesh: mesh, width: width, color: .white,
                                         dash: .init(on: dashOn, off: dashOff, phase: phase),
                                         transform: transform))
        scene.items.append(.strokeCached(mesh: mesh, width: width, color: .black,
                                         dash: .init(on: dashOn, off: dashOff, phase: phase + phaseModulo / 2),
                                         transform: transform))
    }
}
