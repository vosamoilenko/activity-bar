import SwiftUI

/// Status item label view shown in the menu bar
struct StatusItemLabelView: View {
    var body: some View {
        Image(systemName: "brain.head.profile")
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 14, weight: .regular))
            .frame(width: 18, height: 18)
    }
}

#Preview {
    StatusItemLabelView()
}
