import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.didBootstrap {
                ProgressView().controlSize(.large)
            } else if let store = model.selectedStore {
                MailView(store: store)
                    .id(store.id)
                    .sheet(isPresented: Bindable(model).isAddingAccount) { SignInView(isSheet: true) }
            } else {
                SignInView(isSheet: false)
            }
        }
    }
}
