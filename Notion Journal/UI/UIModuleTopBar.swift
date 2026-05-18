import SwiftUI

struct ModuleTopBar: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let isOn: Bool
        let action: () -> Void
    }

    let items: [Item]

    private var itemW: CGFloat { 92 }
    private var itemH: CGFloat { 36 }
    private var fontSize: CGFloat { 11 }
    private var itemSpacing: CGFloat { 8 }

    var body: some View {
        HStack(spacing: itemSpacing) {
            ForEach(items) { item in
                Button {
                    item.action()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(item.isOn ? Color.accentColor.opacity(0.22) : Color(UIColor.secondarySystemBackground))
                        Text(item.title)
                            .font(.system(size: fontSize, weight: .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(width: itemW - 14)
                            .foregroundStyle(.primary)
                    }
                    .frame(width: itemW, height: itemH)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

struct ModuleToolbarButtons: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let isOn: Bool
        let badgeCount: Int
        let action: () -> Void

        init(
            id: String,
            title: String,
            systemImage: String,
            isOn: Bool,
            badgeCount: Int = 0,
            action: @escaping () -> Void
        ) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
            self.isOn = isOn
            self.badgeCount = badgeCount
            self.action = action
        }
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                Button {
                    item.action()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Label(item.title, systemImage: item.systemImage)
                            .labelStyle(.iconOnly)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(item.isOn ? Color.accentColor.opacity(0.22) : Color(UIColor.secondarySystemBackground))
                            )
                        if item.badgeCount > 0 {
                            Text(item.badgeCount > 99 ? "99+" : "\(item.badgeCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red)
                                .clipShape(Capsule())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
