/*
<samplecode>
  <abstract>
  Declares the Objective-C class that syncs a directory of save files with an
  iCloud CloudKit container, exposing sync, upload, and conflict-resolution
  entry points.
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

#import <Foundation/Foundation.h>

typedef enum CloudSaveLocality : NSInteger {
    CloudSaveLocalityLocal = 0,
    CloudSaveLocalityServer = 1
} CloudSaveLocality;

@interface CloudSaveDeviceInformation : NSObject
@property(readonly) CloudSaveLocality locality;
@property(readonly, nullable) NSString* deviceName;
@property(readonly, nullable) NSArray<NSString*>* files;
@property(readonly, nullable) NSDate* lastFileModification;
@end

@interface CloudSaveConflict : NSObject
@property(readonly, nonnull) CloudSaveDeviceInformation* localSaveInformation;
@property(readonly, nonnull) CloudSaveDeviceInformation* serverSaveInformation;
@end

@interface CloudSaveManager : NSObject

- (instancetype _Nonnull) initWithCloudIdentifier:(NSString* _Nonnull) identifier
                                 saveDirectoryURL:(NSURL* _Nonnull) saveDirectoryURL;

- (instancetype _Nonnull) initWithCloudIdentifier:(NSString* _Nonnull) identifier
                                 saveDirectoryURL:(NSURL* _Nonnull) saveDirectoryURL
                                           filter:(NSPredicate* _Nonnull) predicate
                                      databaseURL:(NSURL* _Nonnull) databaseURL;

/// Syncs the save folder with the server, downloading or uploading as needed.
- (void) syncWithCompletionHandler:(void (^ _Nullable)(BOOL conflictDetected, NSError* _Nullable error)) completionHandler;

/// Uploads local changes; conflicts and errors can be deferred to the next sync.
- (void) uploadWithCompletionHandler:(void (^ _Nullable)(BOOL conflictDetected, NSError* _Nullable error)) completionHandler;

/// Resolves the conflict, as `unresolvedConflict` describes.
- (void) resolveConflictWithLocality:(CloudSaveLocality) device
                   completionHandler:(void (^ _Nullable)(BOOL otherConflictDetected, NSError* _Nullable error)) completionHandler;

@property(readonly, nullable) CloudSaveConflict* unresolvedConflict;
@property(readonly, nonnull) NSURL* saveDirectory;
@property(readonly, nonnull) NSPredicate* saveDirectoryFilter;

@end
