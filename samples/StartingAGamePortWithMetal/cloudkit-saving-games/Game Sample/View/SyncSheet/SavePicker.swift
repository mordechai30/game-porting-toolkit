/*
<samplecode>
  <abstract>
  A view for the sync sheet to show that the sync results in a conflict and the user needs to pick a save.
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

enum SaveVersion {
    case cloud, local
}

struct SavePicker: View {
    @Environment(\.dismiss) var dismiss
    @Environment(GameSaveModel.self) var gsm: GameSaveModel
    
    @Binding var selectedVersion: SaveVersion?
    
    var body: some View {
        NavigationStack {
            VStack {
                
                HStack {
                    Spacer()
                    Text("Which save do you want to keep?")
                        .font(.largeTitle)
                        .bold()
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                
                Spacer()
                
                List {
                    Picker("Select a save", //The picker's title.
                           selection: $selectedVersion, //The binding variable.
                           content: {
                        SavePickerCell(saveVersion: .cloud,
                                       saveInformation: gsm.cloudConflict?.serverSaveInformation)
                        .tag(Optional(SaveVersion.cloud))
                        SavePickerCell(saveVersion: .local,
                                       saveInformation: gsm.cloudConflict?.localSaveInformation)
                        .tag(Optional(SaveVersion.local))
                    })
                    .pickerStyle(.inline)
                }
                .listStyle(.inset)
                .frame(height: 200)
            }
            Spacer(minLength: 20)
            Button("Select") {
                dismiss()
            }
            .bold()
            .buttonStyle(.borderedProminent)
            .opacity(selectedVersion == nil ? 0 : 1)
            .disabled(selectedVersion == nil)
            .animation(.default, value: selectedVersion)
        }
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
                SavePicker(selectedVersion: $selectedVersion)
                    .environment(GameSaveModel.shared)
            }
            
            .onChange(of: selectedVersion) { oldValue, newValue in
                print("newValue: \(String(describing: selectedVersion)) \(String(describing: newValue))")
            }
        }
    }
    
    return ContainerView()
}
