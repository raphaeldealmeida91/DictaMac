import SwiftUI

struct MenuBarIcon: View {
    @ObservedObject var activity: AppActivityModel

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel(accessibilityLabel)
    }

    private var symbol: String {
        switch activity.state {
        case .idle: "mic"
        case .recording: "record.circle.fill"
        case .transcribing, .injecting: "text.bubble.fill"
        }
    }

    private var accessibilityLabel: String {
        switch activity.state {
        case .idle: "DictaMac prêt"
        case .recording: "DictaMac enregistre"
        case .transcribing, .injecting: "DictaMac transcrit"
        }
    }
}
