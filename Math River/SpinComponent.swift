//
//  SpinComponent.swift
//  Math River
//
//  Created by Jens Somers on 22/08/2026.
//

import RealityKit

/// A component that spins the entity around a given axis.
struct SpinComponent: Component {
    let spinAxis: SIMD3<Float> = [0, 1, 0]
}
