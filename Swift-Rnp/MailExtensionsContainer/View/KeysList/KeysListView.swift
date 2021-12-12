//
//  KeysListView.swift
//  Ribose container
//
//  Created by Sergey Vinogradov on 12.12.2021.
//

import SwiftUI

struct KeysListView: View {
    var model: KeysListViewModel
    
    var body: some View {
        Table {
            TableColumn("Filename", value: \.filename)
        } rows: {
            ForEach(model.keyFiles) { value in
                TableRow(value)
            }
        }
    }
}

#if DEBUG
struct KeysListView_Previews: PreviewProvider {
    static var previews: some View {
        KeysListView(model: KeysListViewModel(manager: KeysManager.mock))
    }
}
#endif
