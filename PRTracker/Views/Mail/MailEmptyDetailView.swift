import SwiftUI

struct MailEmptyDetailView: View {
    var body: some View {
        ContentUnavailableView("No Pull Request Selected",
                               systemImage: "arrow.triangle.pull",
                               description: Text("Select a pull request from the sidebar."))
    }
}
