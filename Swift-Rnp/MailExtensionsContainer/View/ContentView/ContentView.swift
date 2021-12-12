//
//  ContentView.swift
//  MailExtensionsContainer
//
//  Created by Sergey Vinogradov on 30.11.2021.
//

import SwiftUI

struct ContentView: View {
    var model: ContentViewModel
    
    var body: some View {
        VStack {
            Text("Keys manager")
            
            HStack {
                Group {
                    Button {} label: {
                        Image(systemName: "plus.circle")
                    }
                    
                    Button {} label: {
                        Image(systemName: "minus.circle")
                    }
                    .disabled(true)
                    
                    Button {} label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    
                    Button {} label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(true)
                }
                .font(.system(size: 40))
                .buttonStyle(.borderless)
            }
            .padding()
            
            KeysListView(model: model.listModel)
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(model: ContentViewModel(manager: KeysManager.mock))
    }
}
#endif
