// Auto-generated from dstar-1.0/fighter1_bsp.h — do not hand-edit.
// Regenerate with tools/parse_fighter.py if the legacy header changes.

import simd

struct FighterPolygon {
    let color: Int16
    let normal: SIMD3<Float>
    let vertices: [SIMD3<Float>]
    /// BSP_BACK_VIEW — render even when viewed from the back side.
    let doubleSided: Bool
}

enum FighterMesh {
    /// 26 polygons ported from the legacy fighter1_bsp.h.
    static let fighter1: [FighterPolygon] = [
        // bn22
        FighterPolygon(
            color: 4,
            normal: SIMD3<Float>(0.7071, -0.7071, 0),
            vertices: [
                SIMD3<Float>(-0.5, -0.1, 1.2),
                SIMD3<Float>(-0.5, -0.1, 0.8),
                SIMD3<Float>(-1.5, -1.1, -0.2),
                SIMD3<Float>(-1.5, -1.1, 0.2),
            ],
            doubleSided: true
        ),
        // bn19
        FighterPolygon(
            color: 2,
            normal: SIMD3<Float>(0.7071, 0.7071, 0),
            vertices: [
                SIMD3<Float>(-0.5, 0.1, 1.2),
                SIMD3<Float>(-0.5, 0.1, 0.8),
                SIMD3<Float>(-1.5, 1.1, -0.2),
                SIMD3<Float>(-1.5, 1.1, 0.2),
            ],
            doubleSided: true
        ),
        // bn20
        FighterPolygon(
            color: 4,
            normal: SIMD3<Float>(-0.7071, 0.7071, 0),
            vertices: [
                SIMD3<Float>(0.5, 0.1, 1.2),
                SIMD3<Float>(0.5, 0.1, 0.8),
                SIMD3<Float>(1.5, 1.1, -0.2),
                SIMD3<Float>(1.5, 1.1, 0.2),
            ],
            doubleSided: true
        ),
        // bn21
        FighterPolygon(
            color: 2,
            normal: SIMD3<Float>(-0.7071, -0.7071, 0),
            vertices: [
                SIMD3<Float>(0.5, -0.1, 1.2),
                SIMD3<Float>(0.5, -0.1, 0.8),
                SIMD3<Float>(1.5, -1.1, -0.2),
                SIMD3<Float>(1.5, -1.1, 0.2),
            ],
            doubleSided: true
        ),
        // bn1
        FighterPolygon(
            color: 4,
            normal: SIMD3<Float>(-0.7071, 0.7071, 0),
            vertices: [
                SIMD3<Float>(-0.5, 0.1, 0),
                SIMD3<Float>(-0.25, 0.35, 0),
                SIMD3<Float>(-0.25, 0.35, 2),
                SIMD3<Float>(-0.5, 0.1, 2),
            ],
            doubleSided: false
        ),
        // bn2
        FighterPolygon(
            color: 3,
            normal: SIMD3<Float>(0, 1, 0),
            vertices: [
                SIMD3<Float>(-0.25, 0.35, 0),
                SIMD3<Float>(0.25, 0.35, 0),
                SIMD3<Float>(0.25, 0.35, 2),
                SIMD3<Float>(-0.25, 0.35, 2),
            ],
            doubleSided: false
        ),
        // bn3
        FighterPolygon(
            color: 2,
            normal: SIMD3<Float>(0.7071, 0.7071, 0),
            vertices: [
                SIMD3<Float>(0.5, 0.1, 2),
                SIMD3<Float>(0.25, 0.35, 2),
                SIMD3<Float>(0.25, 0.35, 0),
                SIMD3<Float>(0.5, 0.1, 0),
            ],
            doubleSided: false
        ),
        // bn5
        FighterPolygon(
            color: 4,
            normal: SIMD3<Float>(0.7071, -0.7071, 0),
            vertices: [
                SIMD3<Float>(0.5, -0.1, 0),
                SIMD3<Float>(0.25, -0.35, 0),
                SIMD3<Float>(0.25, -0.35, 2),
                SIMD3<Float>(0.5, -0.1, 2),
            ],
            doubleSided: false
        ),
        // bn6
        FighterPolygon(
            color: 3,
            normal: SIMD3<Float>(0, -1, 0),
            vertices: [
                SIMD3<Float>(-0.25, -0.35, 2),
                SIMD3<Float>(0.25, -0.35, 2),
                SIMD3<Float>(0.25, -0.35, 0),
                SIMD3<Float>(-0.25, -0.35, 0),
            ],
            doubleSided: false
        ),
        // bn7
        FighterPolygon(
            color: 3,
            normal: SIMD3<Float>(-0.7071, -0.7071, 0),
            vertices: [
                SIMD3<Float>(-0.5, -0.1, 2),
                SIMD3<Float>(-0.25, -0.35, 2),
                SIMD3<Float>(-0.25, -0.35, 0),
                SIMD3<Float>(-0.5, -0.1, 0),
            ],
            doubleSided: false
        ),
        // bn4
        FighterPolygon(
            color: 3,
            normal: SIMD3<Float>(1, 0, 0),
            vertices: [
                SIMD3<Float>(0.5, 0.1, 0),
                SIMD3<Float>(0.5, -0.1, 0),
                SIMD3<Float>(0.5, -0.1, 2),
                SIMD3<Float>(0.5, 0.1, 2),
            ],
            doubleSided: false
        ),
        // bn8
        FighterPolygon(
            color: 2,
            normal: SIMD3<Float>(-1, 0, 0),
            vertices: [
                SIMD3<Float>(-0.5, 0.1, 2),
                SIMD3<Float>(-0.5, -0.1, 2),
                SIMD3<Float>(-0.5, -0.1, 0),
                SIMD3<Float>(-0.5, 0.1, 0),
            ],
            doubleSided: false
        ),
        // bn18
        FighterPolygon(
            color: 5,
            normal: SIMD3<Float>(0, 0, -1),
            vertices: [
                SIMD3<Float>(-0.5, -0.1, 0),
                SIMD3<Float>(-0.25, -0.35, 0),
                SIMD3<Float>(0.25, -0.35, 0),
                SIMD3<Float>(0.5, -0.1, 0),
                SIMD3<Float>(0.5, 0.1, 0),
                SIMD3<Float>(0.25, 0.35, 0),
                SIMD3<Float>(-0.25, 0.35, 0),
                SIMD3<Float>(-0.5, 0.1, 0),
            ],
            doubleSided: false
        ),
        // bn9
        FighterPolygon(
            color: 4,
            normal: SIMD3<Float>(-0.4082, 0.4082, 0.8165),
            vertices: [
                SIMD3<Float>(-0.5, 0.1, 2),
                SIMD3<Float>(-0.25, 0.35, 2),
                SIMD3<Float>(-0.25, 0.1, 2.5),
            ],
            doubleSided: false
        ),
        // bn10
        FighterPolygon(
            color: 7,
            normal: SIMD3<Float>(0, 0.4472, 0.8944),
            vertices: [
                SIMD3<Float>(-0.25, 0.35, 2),
                SIMD3<Float>(0.25, 0.35, 2),
                SIMD3<Float>(0.25, 0.1, 2.5),
                SIMD3<Float>(-0.25, 0.1, 2.5),
            ],
            doubleSided: false
        ),
        // bn11
        FighterPolygon(
            color: 2,
            normal: SIMD3<Float>(0.4082, 0.4082, 0.8165),
            vertices: [
                SIMD3<Float>(0.25, 0.1, 2.5),
                SIMD3<Float>(0.25, 0.35, 2),
                SIMD3<Float>(0.5, 0.1, 2),
            ],
            doubleSided: false
        ),
        // bn12
        FighterPolygon(
            color: 2,
            normal: SIMD3<Float>(0.4472, 0, 0.8944),
            vertices: [
                SIMD3<Float>(0.5, 0.1, 2),
                SIMD3<Float>(0.5, -0.1, 2),
                SIMD3<Float>(0.25, -0.1, 2.5),
                SIMD3<Float>(0.25, 0.1, 2.5),
            ],
            doubleSided: false
        ),
        // bn13
        FighterPolygon(
            color: 4,
            normal: SIMD3<Float>(0.4082, -0.4082, 0.8165),
            vertices: [
                SIMD3<Float>(0.5, -0.1, 2),
                SIMD3<Float>(0.25, -0.35, 2),
                SIMD3<Float>(0.25, -0.1, 2.5),
            ],
            doubleSided: false
        ),
        // bn14
        FighterPolygon(
            color: 4,
            normal: SIMD3<Float>(0, -0.4472, 0.8944),
            vertices: [
                SIMD3<Float>(-0.25, -0.1, 2.5),
                SIMD3<Float>(0.25, -0.1, 2.5),
                SIMD3<Float>(0.25, -0.35, 2),
                SIMD3<Float>(-0.25, -0.35, 2),
            ],
            doubleSided: false
        ),
        // bn15
        FighterPolygon(
            color: 2,
            normal: SIMD3<Float>(-0.4082, -0.4082, 0.8165),
            vertices: [
                SIMD3<Float>(-0.25, -0.1, 2.5),
                SIMD3<Float>(-0.25, -0.35, 2),
                SIMD3<Float>(-0.5, -0.1, 2),
            ],
            doubleSided: false
        ),
        // bn16
        FighterPolygon(
            color: 2,
            normal: SIMD3<Float>(-0.4472, 0, 0.8944),
            vertices: [
                SIMD3<Float>(-0.25, 0.1, 2.5),
                SIMD3<Float>(-0.25, -0.1, 2.5),
                SIMD3<Float>(-0.5, -0.1, 2),
                SIMD3<Float>(-0.5, 0.1, 2),
            ],
            doubleSided: false
        ),
        // bn17
        FighterPolygon(
            color: 7,
            normal: SIMD3<Float>(0, 0, 1),
            vertices: [
                SIMD3<Float>(0.25, 0.1, 2.5),
                SIMD3<Float>(0.25, -0.1, 2.5),
                SIMD3<Float>(-0.25, -0.1, 2.5),
                SIMD3<Float>(-0.25, 0.1, 2.5),
            ],
            doubleSided: false
        ),
        // bn23
        FighterPolygon(
            color: 5,
            normal: SIMD3<Float>(-0.7071, 0.7071, 0),
            vertices: [
                SIMD3<Float>(-1.7, 0.9, 1),
                SIMD3<Float>(-1.7, 0.9, -1),
                SIMD3<Float>(-1.3, 1.3, -1),
                SIMD3<Float>(-1.3, 1.3, 1),
            ],
            doubleSided: true
        ),
        // bn24
        FighterPolygon(
            color: 5,
            normal: SIMD3<Float>(0.7071, 0.7071, 0),
            vertices: [
                SIMD3<Float>(1.7, 0.9, 1),
                SIMD3<Float>(1.7, 0.9, -1),
                SIMD3<Float>(1.3, 1.3, -1),
                SIMD3<Float>(1.3, 1.3, 1),
            ],
            doubleSided: true
        ),
        // bn25
        FighterPolygon(
            color: 5,
            normal: SIMD3<Float>(0.7071, -0.7071, 0),
            vertices: [
                SIMD3<Float>(1.7, -0.9, 1),
                SIMD3<Float>(1.7, -0.9, -1),
                SIMD3<Float>(1.3, -1.3, -1),
                SIMD3<Float>(1.3, -1.3, 1),
            ],
            doubleSided: true
        ),
        // bn26
        FighterPolygon(
            color: 5,
            normal: SIMD3<Float>(-0.7071, -0.7071, 0),
            vertices: [
                SIMD3<Float>(-1.7, -0.9, 1),
                SIMD3<Float>(-1.7, -0.9, -1),
                SIMD3<Float>(-1.3, -1.3, -1),
                SIMD3<Float>(-1.3, -1.3, 1),
            ],
            doubleSided: true
        ),
    ]
}
