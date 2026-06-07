/*
<samplecode>
  <abstract>
  Extension to the game-save model to perform file operations.
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

// File-action log lines use the 💾 emoji prefix to make on-disk save events
// scannable in Console.app filters, distinct from cloud / error events
// emitted from the same Logger category.
fileprivate extension Logger {
    static let gameSaveModelFile = Logger(subsystem: Self.loggingSubsystem, category: "GameSaveModel+File")
}

extension GameSaveModel {
    private var fileManager: FileManager { FileManager.default }
    
    typealias SaveConfig = Config.SavePath
    typealias ValidSaveFile = (localIdentifier: SaveGameRecord.LocalIdentifier, fileURL: URL)
    
    // MARK: - File actions
    
    func url(slot: SaveGameRecord.LocalIdentifier) throws -> URL {
        guard slot > 0 && slot <= Config.maxSaveGameCount else {
            Logger.gameSaveModelFile.error("Slot \(slot) is not in range.")
            throw GameSaveModelError.invalidSaveSlot("\(slot)")
        }
        
        return url(slotString: "\(slot)")
    }
    
    func url(slotString: String) -> URL {
        return Config.saveFolderDirectory
            .appending(path: "\(SaveConfig.slotPrefix)-\(slotString)", directoryHint: .isDirectory)
            .appending(path: SaveConfig.filename, directoryHint: .notDirectory)
            .appendingPathExtension(SaveConfig.fileExtension)
    }
    
    func validURLs() -> [URL] {
        var validURLs = [URL]()
        for index: UInt in 1...Config.maxSaveGameCount {
            try? validURLs.append(url(slot: index))
        }
        return validURLs
    }
    
    var potentialValidSaveFiles: [ValidSaveFile] {
        var validSaveFiles = [ValidSaveFile]()
        for index: UInt in 1...Config.maxSaveGameCount {
            try? validSaveFiles.append(ValidSaveFile(localIdentifier: index, fileURL: url(slot: index)))
        }
        return validSaveFiles
    }
    
    func discoverSaveFiles() -> [ValidSaveFile] {
        guard let items = fileManager
            .enumerator(at: Config.saveFolderDirectory,
                        includingPropertiesForKeys: [.isDirectoryKey, .nameKey])?.allObjects as? [URL]
        else { return [] }
        
        let fileURLs = items
            .filter { ((try? !($0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? true)) ?? true) }
            .map { $0.standardizedFileURL }
                
        let discoveredSaveFiles = potentialValidSaveFiles.filter { fileURLs.contains($0.fileURL) }
        Logger.gameSaveModelFile.info("💾 Discovered games on local storage: \(discoveredSaveFiles)")
        return discoveredSaveFiles
    }
    
    func loadSaveFile(_ file: ValidSaveFile) throws -> SaveGameRecord {
        Logger.gameSaveModelFile.log("💾 Loading game from device storage: \(String(describing: file))")
        
        let data = try Data(contentsOf: file.fileURL)
        
        let decoder = Config.PreferredDecoder()
        let saveGame = try decoder.decode(SaveGame.self, from: data)
        
        Logger.gameSaveModelFile.log("💾 Loaded game from device storage: \(String(describing: file))")
        
        return .init(localIdentifier: file.localIdentifier, game: saveGame)
    }
    
    func writeSaveFile(content: SaveGame, to slot: SaveGameRecord.LocalIdentifier) throws {
        guard let fileURL = try? url(slot: slot) else {
            Logger.gameSaveModelFile.error("File URL is not valid.")
            return
        }
                
        let folderURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        let encoder = Config.PreferredEncoder()
        let encodedContent = try encoder.encode(content)
        
        Logger.gameSaveModelFile.log("💾 Writing game \(slot) to device storage.")
        try encodedContent.write(to: fileURL, options: [.atomic, .completeFileProtection])
        Logger.gameSaveModelFile.log("💾 Wrote game \(slot) to device storage \(fileURL).")
        
        Task {
            do {
                guard let cloudSaveManager = cloudSaveManager else {
                    Logger.gameSaveModelFile.log("Skipping upload, because cloudSaveManager is nil.")
                    return
                }
                
                let hasConflict = try await cloudSaveManager.upload()
                if hasConflict {
                    Logger.gameSaveModelFile.log("Conflict: \(self.cloudConflict)")
                }
            } catch {
                Logger.gameSaveModelFile.error("Could not upload to cloud: \(error)")
            }
        }
    }
    
    func deleteSaveFile(at slot: SaveGameRecord.LocalIdentifier) throws {
        Logger.gameSaveModelFile.log("💾 Deleting game \(slot) on device storage.")
        
        if let fileURL = try? url(slot: slot) {
            try fileManager.removeItem(at: fileURL)
        }
        Logger.gameSaveModelFile.log("💾 Deleted game \(slot) on device storage.")
    }
}

extension URL {
    var filename: String {
        return self.deletingPathExtension().lastPathComponent
    }
}
