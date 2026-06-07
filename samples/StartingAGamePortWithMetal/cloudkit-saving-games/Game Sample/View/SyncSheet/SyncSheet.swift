/*
<samplecode>
  <abstract>
  Sheet to present when a sync operation needs the player's attention.
  </abstract>
</samplecode>
*/

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
//
// Copyright 2026 Apple Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

import SwiftUI

struct SyncSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(GameSaveModel.self) var gsm: GameSaveModel
    
    @Binding var selectedVersion: SaveVersion?
    
    var body: some View {
        Group {
            if let syncState = gsm.syncState {
                switch syncState {
                case .syncing:
                    SyncProgress()
                case .conflict:
                    SavePicker(selectedVersion: $selectedVersion)
                        .environment(gsm)
                case .exception:
                    SyncException()
                        .environment(gsm)
                }
            } else {
                Label("Done", systemImage: "checkmark")
                    .font(.largeTitle)
            }
        }
        .interactiveDismissDisabled(gsm.syncState != nil)
    }
}

#Preview {
    struct ContainerView: View {
        @State var isPresented = true
        @State var selectedVersion: SaveVersion?
        
        var body: some View {
            VStack {
                Button("Merge") {
                    isPresented = true
                }
                .buttonStyle(.bordered)
                
                Text("\(String(describing: selectedVersion))")
                    .padding()
            }
            
            .sheet(isPresented: $isPresented) {
                SyncSheet(selectedVersion: $selectedVersion)
                    .environment(GameSaveModel.shared)
            }
        }
    }
    
    return ContainerView()
}
