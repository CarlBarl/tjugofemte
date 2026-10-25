import SwiftUI

/// "Keep up to 12 months on this phone?", asked once: before the setup's first step, and from the upgrade card. The bank
/// hands over 90 days at a time, so how long the phone keeps them is what lets the history behind the averages grow.
struct RetentionPromptView: View {
    /// Months to keep: 12 or 3.
    let choose: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Screen(spacing: 24) {
                Spacer().frame(height: 32)
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "History")
                    Text("Keep up to 12 months on this phone?").appFont(size: 34, weight: .bold, rounded: true).foregroundStyle(Tokens.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your bank gives 90 days at a time, so the analysis grows as months build up.")
                        .appFont(size: 17).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
                }
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        point("calendar", "Steadier numbers", "What you usually spend and your savings rate are averages over up to 12 complete periods.")
                        Hairline()
                        point("iphone", "Only on this phone", "Anything older is deleted. You can change the length in Settings.")
                    }
                }
            }
            VStack(spacing: 4) {
                BigButton(title: "Keep 12 months") { choose(12) }
                TextAction(title: "Keep 3 months") { choose(3) }
            }
            .padding(.horizontal, Tokens.screenPadding)
            .padding(.vertical, 12)
        }
        .background(Tokens.bg)
    }

    private func point(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryGlyph(symbol: symbol).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).appFont(size: 16, weight: .semibold).foregroundStyle(Tokens.text)
                Text(text).appFont(size: 14).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
