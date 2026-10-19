import simd

enum WorldPositionError: Error, Equatable {
    case nonfiniteOffset
    case outOfRange
}

/// A universal address, not a renderer transform. Each sector spans 2^32 metres.
/// Int64 sectors cover over 4 trillion light-years in either direction; bounded
/// Double offsets retain submillimetre detail independent of distance from zero.
struct WorldPosition: Equatable {
    static let sectorSize: Double = 4_294_967_296
    static let zero = WorldPosition()
    private(set) var sector: SIMD3<Int64> = .zero
    private(set) var offset: SIMD3<Double> = .zero

    private init() {}

    init(sector: SIMD3<Int64> = .zero, offset: SIMD3<Double> = .zero) throws {
        self.sector = sector
        self.offset = .zero
        self = try adding(metres: offset)
    }

    func adding(metres delta: SIMD3<Double>) throws -> WorldPosition {
        var result = self
        for axis in 0..<3 {
            guard delta[axis].isFinite else { throw WorldPositionError.nonfiniteOffset }
            // Split before adding to the local offset, preserving small accumulated terms.
            let quotient = (delta[axis] / Self.sectorSize).rounded(.towardZero)
            guard let whole = Int64(exactly: quotient) else { throw WorldPositionError.outOfRange }
            let (address, overflow) = sector[axis].addingReportingOverflow(whole)
            guard !overflow else { throw WorldPositionError.outOfRange }
            var local = offset[axis] + (delta[axis] - quotient * Self.sectorSize)
            var carry: Int64 = 0
            if local >= Self.sectorSize / 2 { local -= Self.sectorSize; carry = 1 }
            if local < -Self.sectorSize / 2 { local += Self.sectorSize; carry = -1 }
            let (normalized, carryOverflow) = address.addingReportingOverflow(carry)
            guard !carryOverflow else { throw WorldPositionError.outOfRange }
            result.sector[axis] = normalized
            result.offset[axis] = local
        }
        return result
    }

    /// Subtract integer addresses first. Only the relative distance becomes Double.
    /// Distant objects need not retain local detail in this approximate relative result;
    /// nearby objects always retain it, even at the edge of the universal address range.
    func metres(relativeTo origin: WorldPosition) -> SIMD3<Double> {
        var result = SIMD3<Double>.zero
        for axis in 0..<3 {
            let (difference, overflow) = sector[axis].subtractingReportingOverflow(origin.sector[axis])
            let sectors = overflow ? Double(sector[axis]) - Double(origin.sector[axis]) : Double(difference)
            result[axis] = sectors * Self.sectorSize + (offset[axis] - origin.offset[axis])
        }
        return result
    }
}

/// A location in a named frame. Resolving relative to another location uses their
/// common ancestor before introducing a universal address or a distant parent.
struct WorldLocation {
    let frame: String
    var offset: SIMD3<Double> = .zero
}
