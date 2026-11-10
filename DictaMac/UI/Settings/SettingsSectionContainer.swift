import SwiftUI

struct SettingsSectionContainer<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                Text(title)
                    .font(.largeTitle.bold())
                content
            }
            .frame(maxWidth: Theme.Settings.contentMaximumWidth, alignment: .leading)
            .padding(Theme.Spacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.background)
    }
}
