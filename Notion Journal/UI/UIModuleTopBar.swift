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
                .disabled(item.id == "outline")
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
        let action: () -> Void
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                Button {
                    item.action()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(item.isOn ? Color.accentColor.opacity(0.22) : Color(UIColor.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
                .disabled(item.id == "outline")
            }
        }
    }
}
