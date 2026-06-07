/*
<samplecode>
  <abstract>
  Header for the helper class that simplifies writing tests.
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

#ifndef CloudSaveTestHelper_h
#define CloudSaveTestHelper_h

#import "CloudSaveManager.h"

@interface CloudSaveTestHelper : NSObject

- (instancetype) initWithName:(NSString*) name;

- (instancetype) initWithName:(NSString*) name filter:(NSPredicate*) predicate;

- (void) createFile:(NSString*)filename content:(NSString*) content;
- (void) writeFile:(NSString*)filename content:(NSString*) content;
- (void) deleteFile:(NSString*)filename;
- (void) deleteAllFiles; // Delete all but the database.
- (void) deleteDatabase; // Delete only the database.
- (void) checkFile:(NSString*)filename withContent:(NSString*) content;
- (BOOL) fileExists:(NSString*)filename;


- (void) syncAndWaitNoError;
- (void) syncAndWait:(void (^)(BOOL conflictDetected, NSError * error)) finishSync;

- (void) uploadAndWaitNoError;
- (void) uploadAndWait:(void (^)(BOOL conflictDetected, NSError * error)) finishUpload;

- (void) resolveAndWait:(CloudSaveLocality)locality completionHandler:(void (^)(BOOL otherConflictDetected, NSError *))completionHandler;

@property CloudSaveManager* manager;

@end

#endif /* CloudSaveTestHelper_h */
