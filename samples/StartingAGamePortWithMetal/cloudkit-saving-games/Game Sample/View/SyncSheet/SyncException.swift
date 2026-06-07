/*
<samplecode>
  <abstract>
  A view for the sync sheet to show that the sync has some errors or exception.
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

struct SyncException: View {
    @Environment(\.dismiss) var dismiss
    @Environment(GameSaveModel.self) var gsm: GameSaveModel
    
    var body: some View {
        VStack {
            
            Spacer()
            Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .font(.largeTitle)
                .padding()
            Text("Could not sync right now.")
                .font(.headline)
            
            Spacer()
            
            Button("Try again") {
                Task {
                    await gsm.sync()
                }
            }
            .buttonStyle(.borderedProminent)
            
            Button("Skip") {
                dismiss()
            }
            .buttonStyle(.bordered)
            
        }
    }
}

#Preview {
    SyncException()
}
