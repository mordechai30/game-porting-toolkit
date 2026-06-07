/*
<samplecode>
  <abstract>
  Row item view for the save picker to show each saved version.
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

struct SavePickerCell: View {
    
    let saveVersion: SaveVersion
    
    let saveInformation: CloudSaveDeviceInformation?
    
    var body: some View {
        HStack {
            Image(systemName: systemImageNameBySaveVersion)
                .font(.title)
                .foregroundColor(.accentColor)
            
            LabeledContent {
                Text(localityString)
            } label: {
                Text(saveInformation?.deviceName ?? "Device Name")
                Text(saveInformation?.lastFileModification?.description ?? "Last Modification Date")
            }
        }
    }
    
    var systemImageNameBySaveVersion: String {
        switch saveVersion {
        case .cloud:
            return "cloud"
        case .local:
            return "folder"
        }
    }
    
    var localityString: String {
        let unknownLocalityString = "Locality"
        
        guard let locality = saveInformation?.locality else {
            return unknownLocalityString
        }
        
        switch locality {
        case CloudSaveLocalityLocal:
            return "Local"
        case CloudSaveLocalityServer:
            return "Remote"
        default:
            return unknownLocalityString
        }
    }
}

#Preview {
    List {
        SavePickerCell(saveVersion: .cloud, saveInformation: .init())
        SavePickerCell(saveVersion: .local, saveInformation: .init())
    }
}
