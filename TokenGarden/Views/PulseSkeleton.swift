import SwiftUI

/// Pulse-animated skeleton placeholder shown while the Overview tab does its
/// very first load. Subsequent refreshes keep stale data visible so this
/// rarely (if ever) appears after the app has been running.
struct PulseSkeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 4

    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.primary.opacity(isPulsing ? 0.06 : 0.14))
            .frame(width: width, height: height)
            .onAppear {
                guard !isPulsing else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

/// Rough skeleton for the whole Overview tab — approximate layout matches
/// the real UI so the transition to real content doesn't visibly jump.
struct OverviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Spacer()
                    PulseSkeleton(width: 110, height: 14, cornerRadius: 4)
                }
                PulseSkeleton(height: 132, cornerRadius: 6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            PulseSkeleton(height: 32, cornerRadius: 8)
                .padding(.horizontal, 12)
            PulseSkeleton(height: 32, cornerRadius: 8)
                .padding(.horizontal, 12)
            PulseSkeleton(height: 32, cornerRadius: 8)
                .padding(.horizontal, 12)
            PulseSkeleton(height: 32, cornerRadius: 8)
                .padding(.horizontal, 12)
        }
        .padding(.bottom, 12)
    }
}
