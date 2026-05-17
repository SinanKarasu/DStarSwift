import simd

/// A point-light star in world space.
struct StarPoint {
    var position: SIMD3<Float>
    /// Brightness in 0...1, mapped to alpha/intensity by the renderer.
    var magnitude: Float
    /// Index into the renderer's color palette
    /// (0 = white, 1 = red, 2 = green, 3 = blue), matching the legacy partition.
    var colorIndex: UInt8
}

/// Anything that can hand the renderer a set of stars.
///
/// The original `LegacyStarfield` is one source (a 400-point hand-rolled list
/// on a ~2000-unit sphere shell). `SphericalShellStarfield` is the new
/// procedural default. A future `DESIStarfield` will read DESI catalog data
/// and emit the same `[StarPoint]` shape, so the renderer doesn't have to
/// change when we swap data sources.
protocol StarfieldSource {
    func makeStars() -> [StarPoint]
}

// MARK: - Procedural spherical shell

/// Stars distributed in a thick spherical shell around the origin.
///
/// Random direction (uniform on the unit sphere) and a random radius inside
/// `radiusRange`, so the field has real depth instead of all sitting at the
/// same distance from the camera. Driven by a seeded PRNG so the field is
/// stable from run to run.
struct SphericalShellStarfield: StarfieldSource {
    var starCount: Int = 5_000
    var radiusRange: ClosedRange<Float> = 1_000 ... 8_000
    var seed: UInt64 = 0xD57A_8B0C_0FFE_E101
    /// Same color partition the legacy code used: roughly 5/8 white,
    /// 1/8 red, 1/8 green, 1/8 blue.
    var whiteFraction: Float = 5.0 / 8.0

    func makeStars() -> [StarPoint] {
        var rng = SplitMix64(state: seed)
        var out: [StarPoint] = []
        out.reserveCapacity(starCount)

        let rMin = radiusRange.lowerBound
        let rMax = radiusRange.upperBound
        let otherFraction = (1.0 - whiteFraction) / 3.0

        for i in 0..<starCount {
            // Uniform direction on the unit sphere via inverse-CDF.
            let u1 = rng.unitFloat()
            let u2 = rng.unitFloat()
            let z = 1 - 2 * u1                    // cos(theta), uniform in [-1, 1]
            let r2 = sqrt(max(0, 1 - z * z))      // sin(theta)
            let phi = 2 * Float.pi * u2
            let dir = SIMD3<Float>(r2 * cos(phi), r2 * sin(phi), z)

            // Radius distributed so volume-density is roughly constant
            // across the shell: r = (rMin^3 + u (rMax^3 - rMin^3))^(1/3).
            let u3 = rng.unitFloat()
            let r3 = rMin * rMin * rMin
                + u3 * (rMax * rMax * rMax - rMin * rMin * rMin)
            let radius = pow(r3, 1.0 / 3.0)

            // Faint stars are more numerous than bright ones (mild power law).
            let mag = pow(rng.unitFloat(), 2.2)

            let palette = rng.unitFloat()
            let colorIndex: UInt8
            if palette < whiteFraction {
                colorIndex = 0
            } else if palette < whiteFraction + otherFraction {
                colorIndex = 1
            } else if palette < whiteFraction + 2 * otherFraction {
                colorIndex = 2
            } else {
                colorIndex = 3
            }

            out.append(StarPoint(
                position: dir * radius,
                magnitude: 0.25 + 0.75 * mag,   // never fully invisible
                colorIndex: colorIndex
            ))
            _ = i
        }

        return out
    }
}

// MARK: - Legacy adapter

/// Adapter that exposes the original 400-point list as a `StarfieldSource`,
/// kept around for reference / A-B comparison.
struct LegacyStarfieldSource: StarfieldSource {
    func makeStars() -> [StarPoint] {
        let points = LegacyStarfield.points
        let total = points.count
        let other = total / 8
        let whiteCount = total - other * 3

        return points.enumerated().map { i, p in
            let colorIndex: UInt8
            if i < whiteCount {
                colorIndex = 0
            } else if i < whiteCount + other {
                colorIndex = 1
            } else if i < whiteCount + other * 2 {
                colorIndex = 2
            } else {
                colorIndex = 3
            }
            return StarPoint(position: p, magnitude: 1.0, colorIndex: colorIndex)
        }
    }
}

// MARK: - DESI placeholder

/// Stub for the future DESI catalog loader. See PORTING_PLAN.md.
/// Will eventually parse a FITS/Parquet excerpt of DESI targets and convert
/// (RA, Dec, redshift) to a Cartesian position in the same world frame.
struct DESIStarfieldSource: StarfieldSource {
    var fallback: StarfieldSource = SphericalShellStarfield()
    func makeStars() -> [StarPoint] {
        // TODO: load DESI catalog from bundle / disk and produce real stars.
        return fallback.makeStars()
    }
}

// MARK: - PRNG (deterministic, header-only SplitMix64)

/// SplitMix64 — small, fast, deterministic. Used so the procedural starfield
/// is reproducible across runs without pulling in a full PRNG dependency.
struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }

    /// Float in [0, 1).
    mutating func unitFloat() -> Float {
        // Use top 24 bits → exactly representable in Float32.
        let bits = next() &>> 40
        return Float(bits) / Float(1 << 24)
    }
}
