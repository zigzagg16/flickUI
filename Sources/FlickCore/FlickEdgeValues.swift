import Foundation

/// A value with optional per-edge overrides, keyed by physical edge.
///
/// Reading an edge returns its override when there is one, and the base value otherwise.
public struct FlickEdgeValues<Value> {
    /// The value for edges without an override.
    public var base: Value
    /// Edge-specific values.
    public var overrides: [FlickScreenEdge: Value]

    public init(_ base: Value, overrides: [FlickScreenEdge: Value] = [:]) {
        self.base = base
        self.overrides = overrides
    }

    public subscript(edge: FlickScreenEdge) -> Value {
        get { overrides[edge] ?? base }
        set { overrides[edge] = newValue }
    }
}

extension FlickEdgeValues: Equatable where Value: Equatable {}
extension FlickEdgeValues: Sendable where Value: Sendable {}

extension FlickEdgeValues: ExpressibleByFloatLiteral where Value == CGFloat {
    public init(floatLiteral value: Double) {
        self.init(CGFloat(value))
    }
}

extension FlickEdgeValues: ExpressibleByIntegerLiteral where Value == CGFloat {
    public init(integerLiteral value: Int) {
        self.init(CGFloat(value))
    }
}

/// A value with optional per-edge overrides, keyed by logical edge. This is what the
/// public API stores; it is resolved to physical edges once the layout direction is known.
///
/// Edge-specific values always take precedence over the base value, whatever order
/// they were set in.
public struct FlickEdgeSettings<Value> {
    public var base: Value
    public var overrides: [FlickEdge: Value]

    public init(_ base: Value, overrides: [FlickEdge: Value] = [:]) {
        self.base = base
        self.overrides = overrides
    }

    public subscript(edge: FlickEdge) -> Value {
        get { overrides[edge] ?? base }
        set { overrides[edge] = newValue }
    }

    /// Sets a value for some edges. `.all` replaces the base value and keeps
    /// existing edge-specific overrides.
    public mutating func set(_ value: Value, for edges: FlickEdgeSet) {
        if edges == .all {
            base = value
        } else {
            for edge in edges.edges {
                overrides[edge] = value
            }
        }
    }

    /// The values keyed by physical edge.
    public func resolved(isRightToLeft: Bool) -> FlickEdgeValues<Value> {
        var physical: [FlickScreenEdge: Value] = [:]
        for (edge, value) in overrides {
            physical[edge.resolved(isRightToLeft: isRightToLeft)] = value
        }
        return FlickEdgeValues(base, overrides: physical)
    }
}

extension FlickEdgeSettings: Equatable where Value: Equatable {}
extension FlickEdgeSettings: Sendable where Value: Sendable {}
