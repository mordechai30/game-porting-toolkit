/*
<samplecode>
  <abstract>
  Implementation of a helper class that simplifies writing tests.
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
#import <XCTest/XCTest.h>

#import "CloudSaveTestHelper.h"

#import "CloudSaveTests-Swift.h"

NSString* const containerIdentifier(void)
{
    return  UniversalConfig.containerIdentifier;
};

@implementation CloudSaveTestHelper
{
    NSString* _dbFilename;
}

- (instancetype) initWithName:(NSString*) name filter:(NSPredicate*) predicate {
    self = [super init];
    if (self) {
        _dbFilename = @"cloudstate.db";
        NSURL* tempDirectory = [[NSFileManager defaultManager] temporaryDirectory];
        NSString* saveDirectory = [NSString stringWithFormat:@"%@/CloudSaveTests/%@",
                                    [tempDirectory path],
                                    name];

        [[NSFileManager defaultManager] createDirectoryAtPath:saveDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil error:nil];

        NSURL* saveURL = [NSURL fileURLWithPath:saveDirectory];
        NSURL* stateURL = [NSURL fileURLWithPath:_dbFilename relativeToURL:saveURL];

        _manager = [[CloudSaveManager alloc] initWithCloudIdentifier:containerIdentifier()
                                                    saveDirectoryURL:saveURL
                                                              filter:predicate
                                                         databaseURL:stateURL];

        NSLog(@"Cloud save directory created at path %@", saveDirectory);
    }
    return self;
}

- (instancetype) initWithName:(NSString*) name {
    return [self initWithName:name filter:[NSPredicate predicateWithFormat:@"self.relativePath like '*.save'"]];
}

- (void) createFile:(NSString*)filename 
            content:(NSString*) content {
    NSData* data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSURL* url = [NSURL fileURLWithPath:filename relativeToURL:_manager.saveDirectory];
    NSURL* urlDir = url.URLByDeletingLastPathComponent;

    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:urlDir withIntermediateDirectories:YES attributes:nil error:nil]);
    XCTAssertTrue([[NSFileManager defaultManager] createFileAtPath:url.path contents:data attributes:nil]);
}

- (void) writeFile:(NSString*)filename
            content:(NSString*) content {
    NSData* data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSURL* url = [NSURL fileURLWithPath:filename relativeToURL:_manager.saveDirectory];
    XCTAssertTrue([data writeToURL:url atomically:NO]);
}

- (void) deleteFile:(NSString*)filename {
    NSURL* url = [NSURL fileURLWithPath:filename relativeToURL:_manager.saveDirectory];
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtURL:url error:nil]);
}

- (void) deleteAllFiles {

    NSFileManager* manager = [NSFileManager defaultManager];
    NSDirectoryEnumerationOptions options = NSDirectoryEnumerationProducesRelativePathURLs;

    NSDirectoryEnumerator<NSURL *>* urls = [[NSFileManager defaultManager] enumeratorAtURL:_manager.saveDirectory
                                                                includingPropertiesForKeys:@[NSURLContentModificationDateKey]
                                                                                   options:options
                                                                              errorHandler:nil];

    XCTAssertNotNil(urls);
    for (NSURL* url in urls)  {
        if ([url.relativePath isEqualToString:_dbFilename])
            continue;
        if (!url.hasDirectoryPath)
            XCTAssertTrue([manager removeItemAtURL:url error:nil]);
    }
}

- (void) deleteDatabase {
    NSURL* url = [NSURL fileURLWithPath:_dbFilename relativeToURL:_manager.saveDirectory];
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtURL:url error:nil]);
}

- (void) checkFile:(NSString*) filename
       withContent:(NSString*) expectedContent {
    NSURL* url = [NSURL fileURLWithPath:filename relativeToURL:_manager.saveDirectory];
    NSString* fileContent = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    XCTAssertTrue(fileContent, "File doesn't exist");
    XCTAssertTrue([expectedContent isEqualToString:fileContent], "Unexpected file content");
}

- (void) syncAndWait:(void (^)(BOOL conflictDetected, NSError * error)) finishSync {
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    [self.manager syncWithCompletionHandler:^(BOOL conflictDetected, NSError *error) {
        finishSync(conflictDetected, error);
        dispatch_semaphore_signal(finished);
    }];
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
}

- (void) uploadAndWait:(void (^)(BOOL conflictDetected, NSError * error)) finishUpload {
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    [self.manager uploadWithCompletionHandler:^(BOOL conflictDetected, NSError *error) {
        finishUpload(conflictDetected, error);
        dispatch_semaphore_signal(finished);
    }];
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
}

- (void) resolveAndWait:(CloudSaveLocality)locality completionHandler:(void (^)(BOOL otherConflictDetected, NSError *))completionHandler {
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    [self.manager resolveConflictWithLocality:locality completionHandler:^(BOOL conflictDetected, NSError *error) {
        completionHandler(conflictDetected, error);
        dispatch_semaphore_signal(finished);
    }];
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
}

- (void) syncAndWaitNoError {
    [self syncAndWait:^(BOOL conflictDetected, NSError *error) {
        XCTAssertFalse(conflictDetected);
        XCTAssertNil(error);
        XCTAssertNil(self.manager.unresolvedConflict);
    }];
}

- (void) uploadAndWaitNoError {
    [self uploadAndWait:^(BOOL conflictDetected, NSError *error) {
        XCTAssertFalse(conflictDetected);
        XCTAssertNil(error);
        XCTAssertNil(self.manager.unresolvedConflict);
    }];
}

- (BOOL) fileExists:(NSString*)filename
{
    NSURL* url = [NSURL fileURLWithPath:filename relativeToURL:_manager.saveDirectory];
    return ([[NSFileManager defaultManager] fileExistsAtPath:url.path]);
}

@end
