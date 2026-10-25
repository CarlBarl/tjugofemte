import SwiftUI
import UIKit

/// The pieces every screen is built from, so a card on Overview and a card in Settings are the same card.

/// A scrolling screen: title block, cards 16 pt apart, 20 pt gutters, the ink behind it all.
struct Screen<Content: View>: View {
    var spacing: CGFloat = 16
    /// The four tab roots show the sample-data banner above their content; sheets and pushed screens do not.
    var banner = false
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(.horizontal, Tokens.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // Always there, even with no banner: its ink reaches up behind the status bar, so scrolled text slides under it, not onto the clock.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) { if banner { DemoBanner() } }
                .frame(maxWidth: .infinity)
                .background(Tokens.bg)
        }
        .background(Tokens.bg)
    }
}

/// The uppercase, letter-spaced line above a section or a screen title.
struct SectionLabel: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text)
            .tracking(1.6)
            .appFont(size: 12, weight: .semibold)
            .textCase(.uppercase)
            .foregroundStyle(Tokens.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Label, big title, one line under it.
struct ScreenTitle: View {
    let label: LocalizedStringKey
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: label)
            Text(title).appFont(size: 30, weight: .bold, rounded: true).foregroundStyle(Tokens.text)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle).appFont(size: 15).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }
}

/// The card: the lighter fill, the 6 % hairline, a 16 pt radius.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.card)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous).strokeBorder(Tokens.cardBorder, lineWidth: 1))
    }
}

/// A card of rows, hairlines between them.
struct RowCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) { content }
                .padding(.horizontal, 16)
        }
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Tokens.separator).frame(height: 1) }
}

/// One row: a title, an optional caption, whatever sits on the right.
struct Row<Trailing: View>: View {
    let title: String
    var caption: String? = nil
    var symbol: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let symbol { CategoryGlyph(symbol: symbol) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).appFont(size: 16, weight: .medium).foregroundStyle(Tokens.text).lineLimit(2)
                if let caption {
                    Text(caption).appFont(size: 13).foregroundStyle(Tokens.dim).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 56)
        .padding(.vertical, 6)
    }
}

/// A row that goes somewhere: the chevron on the right.
struct LinkRow<Destination: View>: View {
    let title: String
    var caption: String? = nil
    var value: String? = nil
    var symbol: String? = nil
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink { destination } label: {
            Row(title: title, caption: caption, symbol: symbol) {
                if let value { Text(value).appFont(size: 15).foregroundStyle(Tokens.muted).lineLimit(1) }
                Chevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Chevron: View {
    var body: some View { Image(systemName: "chevron.right").appFont(size: 13, weight: .semibold).foregroundStyle(Tokens.dim) }
}

/// A category's symbol in a soft square.
struct CategoryGlyph: View {
    let symbol: String
    var tint: Color = Tokens.accent
    var body: some View {
        Image(systemName: symbol)
            .appFont(size: 15, weight: .semibold)
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(Tokens.pill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The one big action on a screen: 56 pt, accent, dark text.
struct BigButton: View {
    let title: LocalizedStringKey
    var detail: String? = nil
    var isEnabled = true
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isBusy { ProgressView().tint(Tokens.onAccent) }
                VStack(spacing: 2) {
                    Text(title).appFont(size: 18, weight: .semibold)
                    if let detail { Text(detail).appFont(size: 14, weight: .medium) }
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? Tokens.onAccent : Tokens.dim)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(isEnabled ? Tokens.accent : Tokens.pill)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
    }
}

/// A quiet second action: accent text, full tap height.
struct TextAction: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var tint: Color = Tokens.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .appFont(size: 15, weight: .semibold)
            .foregroundStyle(tint)
            .frame(minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Whole kronor in a pill. Empty shows the placeholder; 0 is a real value.
struct AmountField: View {
    @Binding var value: Decimal
    var placeholder: String = "0"
    var width: CGFloat = 118

    var body: some View {
        TextField(placeholder, value: $value, format: .number.precision(.fractionLength(0)).grouping(.never))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .font(Tokens.numberFont(size: 18, weight: .semibold))
            .foregroundStyle(Tokens.text)
            .padding(.horizontal, 12)
            .frame(width: width, height: Tokens.minimumTapTarget)
            .background(Tokens.pill)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous))
    }
}

/// A short text field in the same pill as the amounts.
struct PillTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .appFont(size: 16, weight: .medium)
            .foregroundStyle(Tokens.text)
            .padding(.horizontal, 12)
            .frame(height: Tokens.minimumTapTarget)
            .background(Tokens.pill)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous))
    }
}

/// A number with a word under it.
struct StatTile: View {
    let label: LocalizedStringKey
    let value: String
    var tint: Color = Tokens.text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Tokens.numberFont(size: 20)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).appFont(size: 12).foregroundStyle(Tokens.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Spent against budget. Fills accent until the budget, coral past it.
struct AmountBar: View {
    let actual: Decimal
    let budget: Decimal?

    var body: some View {
        GeometryReader { geo in
            let fraction = budget.map { $0 > 0 ? min(1, Double(truncating: (actual / $0) as NSNumber)) : (actual > 0 ? 1 : 0) } ?? 0
            let over = budget.map { actual > $0 } ?? false
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.pill)
                Capsule().fill(over ? Tokens.over : Tokens.accent).frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}

/// Something that needs attention, in words, on the tinted ground.
struct Banner: View {
    let message: LocalizedStringKey
    var systemImage = "exclamationmark.circle"
    var tint: Color = Tokens.accent
    var action: (LocalizedStringKey, () -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).appFont(size: 16, weight: .semibold).foregroundStyle(tint).padding(.top, 2)
            Text(message).appFont(size: 14, weight: .medium).foregroundStyle(Tokens.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action: action.1) {
                    Text(action.0).appFont(size: 14, weight: .semibold).foregroundStyle(tint)
                        .frame(minHeight: Tokens.minimumTapTarget).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.ground)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
    }
}

/// A line of small round dots, one per step.
struct StepDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == current ? Tokens.accent : Tokens.pill).frame(width: i == current ? 18 : 6, height: 6)
            }
        }
        .animation(.snappy, value: current)
    }
}

/// A picker as a menu row value: "25th", with the chevron.
struct MenuValue: View {
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Text(text).appFont(size: 15, weight: .medium).foregroundStyle(Tokens.accent)
            Image(systemName: "chevron.up.chevron.down").appFont(size: 11, weight: .semibold).foregroundStyle(Tokens.dim)
        }
        .frame(minHeight: Tokens.minimumTapTarget)
    }
}

extension View {
    /// A system `List` on the ink: hidden grouped background, cards as row backgrounds.
    func appList() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Tokens.bg)
            .listRowBackground(Tokens.card)
    }

    /// The number pad has no return key; one Done above it per screen.
    func keyboardDone() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                    .tint(Tokens.accent)
            }
        }
    }
}
