#if canImport(UIKit)
import SwiftUI

/// An SF Symbols animation for a menu item's symbol.
public struct FlickSymbolEffect: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case none, bounce, pulse, wiggle, breathe, rotate, scale, variableColor
    }

    let kind: Kind
    /// Whether the effect keeps playing while the item is emphasized, rather than once.
    public let repeats: Bool

    init(_ kind: Kind, repeats: Bool = false) {
        self.kind = kind
        self.repeats = repeats
    }

    public static let none = Self(.none)
    public static let bounce = Self(.bounce)
    public static let pulse = Self(.pulse)
    public static let wiggle = Self(.wiggle)
    public static let breathe = Self(.breathe)
    public static let rotate = Self(.rotate)
    /// Scales the symbol up.
    public static let scale = Self(.scale)
    /// Animates the layers of symbols that support variable colour, such as `wifi`.
    public static let variableColor = Self(.variableColor)

    /// The same effect, playing for as long as the item is emphasized.
    public var repeating: Self {
        Self(kind, repeats: true)
    }
}

/// How a menu item looks while it is highlighted or selected.
/// Properties left `nil` keep the row's own appearance.
public struct FlickMenuItemEmphasis {
    /// The colour of the item's symbol and title.
    public var tint: Color?
    /// The symbol variant, such as `.fill` or `.circle`. Symbols without that
    /// variant are drawn as is.
    public var symbolVariant: SymbolVariants?
    public var symbolEffect: FlickSymbolEffect

    public init(tint: Color? = nil, symbolVariant: SymbolVariants? = nil, symbolEffect: FlickSymbolEffect = .none) {
        self.tint = tint
        self.symbolVariant = symbolVariant
        self.symbolEffect = symbolEffect
    }

    /// No emphasis.
    public static var none: Self { Self() }

    /// The default for the highlighted item: a filled symbol that bounces once.
    public static var highlighted: Self { Self(symbolVariant: .fill, symbolEffect: .bounce) }

    /// The default for the selected item: no emphasis.
    public static var selected: Self { Self() }
}

/// Applies a ``FlickSymbolEffect`` to the SF Symbols in a view while `isActive`.
struct FlickSymbolEffectModifier: ViewModifier {
    let effect: FlickSymbolEffect
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let options: SymbolEffectOptions = effect.repeats ? .repeating : .nonRepeating
        switch effect.kind {
        case .none: content
        case .bounce: content.symbolEffect(.bounce, options: options, isActive: isActive)
        case .pulse: content.symbolEffect(.pulse, options: options, isActive: isActive)
        case .wiggle: content.symbolEffect(.wiggle, options: options, isActive: isActive)
        case .breathe: content.symbolEffect(.breathe, options: options, isActive: isActive)
        case .rotate: content.symbolEffect(.rotate, options: options, isActive: isActive)
        case .scale: content.symbolEffect(.scale.up, options: options, isActive: isActive)
        case .variableColor: content.symbolEffect(.variableColor.iterative, options: options, isActive: isActive)
        }
    }
}

/// The bounds of the highlighted item's symbol, for the indicator to sit under it.
struct FlickHighlightedSymbolKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// The bounds of every row's label, for backgrounds that hold the rows.
struct FlickRowLabelBoundsKey: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

/// A menu row's label: the item's SF Symbol and title, with the highlight and
/// selection emphasis applied.
struct FlickMenuItemLabel: View {
    let title: String
    let systemImage: String
    let isHighlighted: Bool
    let isSelected: Bool
    let highlight: FlickMenuItemEmphasis
    let selection: FlickMenuItemEmphasis

    /// The highlight wins over the selection, property by property.
    private var tint: Color? {
        (isHighlighted ? highlight.tint : nil) ?? (isSelected ? selection.tint : nil)
    }

    private var symbolVariant: SymbolVariants {
        (isHighlighted ? highlight.symbolVariant : nil) ?? (isSelected ? selection.symbolVariant : nil) ?? .none
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .symbolVariant(symbolVariant)
                .contentTransition(.symbolEffect(.replace))
                // Both effects stay attached so the view keeps its identity as the state changes.
                .modifier(FlickSymbolEffectModifier(effect: highlight.symbolEffect, isActive: isHighlighted))
                .modifier(FlickSymbolEffectModifier(
                    effect: selection.symbolEffect,
                    isActive: isSelected && !(isHighlighted && highlight.symbolEffect != .none)
                ))
                .anchorPreference(key: FlickHighlightedSymbolKey.self, value: .bounds) { isHighlighted ? $0 : nil }
        }
        .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
    }
}
#endif
