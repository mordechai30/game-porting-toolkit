/*
<samplecode>
  <abstract>
  Extension to the saved-game class to generate random bytes, simulating a larger saved-game file.
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
import Security
import os.log

fileprivate extension Logger {
    static let SaveGameSecurity = Logger(subsystem: Self.loggingSubsystem, category: "SaveGame+Security")
}

extension SaveGame {
    static func generateRandomBytes(_ measurement: Measurement<UnitInformationStorage>) throws -> Data {
        let byteCount = Int(measurement.converted(to: .bytes).value)
        return try generateRandomBytes(byteCount)
    }
    
    private static func generateRandomBytes(_ count: Int) throws -> Data {
        var randomBytes = Data(count: count)
        let status = randomBytes.withUnsafeMutableBytes { (pointer: UnsafeMutableRawBufferPointer) -> OSStatus in
            guard let baseAddress = pointer.baseAddress else { return errSecInvalidPointer }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }

        if status == errSecSuccess {
            return randomBytes
        } else {
            Logger.SaveGameSecurity.error("Can't generate random bytes.")
            throw SaveGameError.randomBytesGenerationFailed
        }
    }
    
    enum SaveGameError: Error {
        case randomBytesGenerationFailed
    }
}
