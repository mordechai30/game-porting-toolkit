/*
<samplecode>
  <abstract>
  Configurations on the sample app ID, save-file size, save-folder directory, and more.
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

import Foundation
import os.log

/// Expose and share the container identifier to unit tests in Objective-C.
/// To avoid overwriting data between unit tests and the sample app,
/// you can use different container identifiers for unit tests and the game (`Config.containerIdentifier` below).
@objc
public class UniversalConfig: NSObject {
    
    @objc public static let containerIdentifier = "iCloud.com.example.apple-samplecode.CloudSaveSampleGame"
    
    private override init() {
        super.init()
    }
}

enum Config {
    
    static let loggingIdentifier = "com.example.apple-samplecode.CloudSaveSampleGame"
    
    /// Before running this sample for the first time, create your iCloud container in Signing & Capabilities settings.
    /// After you set up the iCloud container for build target `SampleGame`, paste the container identifier into this string.
    /// It may take a few minutes for iCloud to set up the container.
    static let containerIdentifier = UniversalConfig.containerIdentifier
    
    /// Limit saved games to preserve storage and help the player manage numerous saves.
    static let maxSaveGameCount: UInt = 5
    
    static let superBigExtraGameSaveDataByteSize = Measurement<UnitInformationStorage>(value: 3, unit: .megabytes)
    
    /// This app stores saved games into a folder that can read as `/rootDirectory/saveFolder/slotPrefix-N/filename.fileExtension`
    ///
    /// Examples when running in iOS:
    /// `/private/var/mobile/Containers/Data/Application/5C76B433-6D86-4D90-95D8-E6CD9B576E03/Documents/SaveGames/Save-1/game.sav`
    /// `/private/var/mobile/Containers/Data/Application/5C76B433-6D86-4D90-95D8-E6CD9B576E03/Documents/SaveGames/Save-2/game.sav`

    ///
    /// `saveFolder/slotPrefix-N/filename.fileExtension` together becomes `SaveGames/Save-1/game.save`
    enum SavePath {
        /// Use the app's `.documentDirectory` to store our saves.
        ///
        /// Example:  `/private/var/mobile/Containers/Data/Application/5C76B433-6D86-4D90-95D8-E6CD9B576E03/Documents/`
        static let rootDirectory = FileManager.SearchPathDirectory.documentDirectory
        static let saveFolder = "SaveGames"
        /// - `saveSlotPrefix` and slot index `N` connect automatically with a dash (`-`), and indexing starts at 1. For example, `Save-1/`.
        static let slotPrefix = "Save"
        static let filename = "game"
        static let fileExtension = "sav"
    }
    
    static let predicate = NSPredicate(format: "self.relativePath like '*.sav'")
    
    static var saveFolderDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appending(path: SavePath.saveFolder, directoryHint: .isDirectory)
    }
    
    static var databaseURL: URL {
        return .init(filePath: "cloudstate.db", relativeTo: Self.saveFolderDirectory)
    }
    
    /// Property list encoder can compress the data, to persist a saved game that requires large amounts of extra data.
    typealias PreferredEncoder = PropertyListEncoder
    typealias PreferredDecoder = PropertyListDecoder
}

// MARK: -

extension Logger {
    static let loggingSubsystem: String = Config.loggingIdentifier
}
