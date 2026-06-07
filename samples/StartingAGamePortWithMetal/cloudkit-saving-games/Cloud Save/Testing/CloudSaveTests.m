/*
<samplecode>
  <abstract>
  Contains tests for the iCloud save manager.
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

#import <XCTest/XCTest.h>
#import "CloudSaveTestHelper.h"

@interface CloudSaveTests : XCTestCase

@end

@implementation CloudSaveTests

- (void) cleanUpStorage {
    CloudSaveTestHelper* save = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave"];

    [save syncAndWait:^(BOOL conflictDetected, NSError *error) {
        XCTAssertFalse(conflictDetected);
        XCTAssertNil(error);
    }];

    [save deleteAllFiles];

    [save syncAndWait:^(BOOL conflictDetected, NSError *error) {
        XCTAssertFalse(conflictDetected);
        XCTAssertNil(error);
    }];

    [[NSFileManager defaultManager] removeItemAtURL:save.manager.saveDirectory error:nil];
}

- (void) removeLocalFolders {
    NSURL* tempDirectory = [[NSFileManager defaultManager] temporaryDirectory];
    NSString* saveDirectory = [NSString stringWithFormat:@"%@/CloudSaveTests", [tempDirectory path]];
    [[NSFileManager defaultManager] removeItemAtPath:saveDirectory error:nil];
}

- (void) setUp {
    [self cleanUpStorage];
    [self removeLocalFolders];
    [self setContinueAfterFailure:NO];
}

- (void) tearDown {
    [self cleanUpStorage];
    [self removeLocalFolders];
}

- (void) testSimpleSync {
    CloudSaveTestHelper* save1 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave1"];

    [save1 syncAndWaitNoError];
    [save1 createFile:@"path/to/test1.save" content:@"content1"];
    [save1 createFile:@"path/to/test2.save" content:@"content2"];
    [save1 syncAndWaitNoError];

    CloudSaveTestHelper* save2 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave2"];

    [save2 syncAndWaitNoError];
    [save2 checkFile:@"path/to/test1.save" withContent:@"content1"];
    [save2 checkFile:@"path/to/test2.save" withContent:@"content2"];
}

- (void) testSimpleSyncSameContent {
    CloudSaveTestHelper* save1 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave1"];

    [save1 syncAndWaitNoError];
    [save1 createFile:@"path/to/test1.save" content:@"content1"];
    [save1 createFile:@"path/to/test2.save" content:@"content1"];
    [save1 syncAndWaitNoError];

    CloudSaveTestHelper* save2 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave2"];

    [save2 syncAndWaitNoError];
    [save2 checkFile:@"path/to/test1.save" withContent:@"content1"];
    [save2 checkFile:@"path/to/test2.save" withContent:@"content1"];
}

- (void) testSimpleUpload {
    CloudSaveTestHelper* save1 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave1"];

    [save1 syncAndWaitNoError];
    [save1 createFile:@"path/to/test1.save" content:@"content1"];
    [save1 uploadAndWaitNoError];
    [save1 writeFile:@"path/to/test1.save" content:@"content2"];
    [save1 createFile:@"path/to/test2.save" content:@"content3"];
    [save1 uploadAndWaitNoError];

    CloudSaveTestHelper* save2 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave2"];

    [save2 syncAndWaitNoError];
    [save2 checkFile:@"path/to/test1.save" withContent:@"content2"];
    [save2 checkFile:@"path/to/test2.save" withContent:@"content3"];
}

- (void) testManyUploads {
    CloudSaveTestHelper* save1 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave1"];

    const NSInteger fileCount = 10;
    const NSInteger uploadCount = 15;

    for (NSInteger fileId = 0; fileId < fileCount; ++fileId)
        [save1 createFile:[NSString stringWithFormat:@"test%li.save", fileId] content:@"content1"];

    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    for (NSInteger i = 0; i < uploadCount; ++i) {
        for (NSInteger fileId = 0; fileId < fileCount; ++fileId)
            [save1 writeFile:[NSString stringWithFormat:@"test%li.save", fileId] content:[NSString stringWithFormat:@"content%li", i]];

        [save1.manager uploadWithCompletionHandler:^(BOOL conflictDetected, NSError *error) {
            XCTAssertFalse(conflictDetected);
            XCTAssertNil(error);
            dispatch_semaphore_signal(finished);
        }];
    }

    for (NSInteger i = 0; i < uploadCount; ++i) {
        dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
    }

    CloudSaveTestHelper* save2 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave2"];

    [save2 syncAndWaitNoError];
    for (NSInteger fileId = 0; fileId < fileCount; ++fileId)
        [save2 checkFile:[NSString stringWithFormat:@"test%li.save", fileId] withContent:[NSString stringWithFormat:@"content%li", uploadCount - 1]];
}

- (void) testPredicate {
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"self.relativePath like '*.txt'"];
    CloudSaveTestHelper* save1 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave1" filter:predicate];

    [save1 syncAndWaitNoError];
    // `CloudSaveTestHelper` only saves *.save files.
    [save1 createFile:@"test1.txt" content:@"content1"];
    [save1 createFile:@"test2.untracked" content:@"content1"];
    [save1 syncAndWaitNoError];

    CloudSaveTestHelper* save2 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave2" filter:predicate];

    [save2 syncAndWaitNoError];
    [save2 checkFile:@"test1.txt" withContent:@"content1"];
    XCTAssertFalse([save2 fileExists:@"test2.untracked"]);
}

- (void) testFileRemoved {
    CloudSaveTestHelper* save1 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave1"];

    [save1 syncAndWaitNoError];
    [save1 createFile:@"test1.save" content:@"content1"];
    [save1 createFile:@"test2.save" content:@"content2"];
    [save1 syncAndWaitNoError];

    CloudSaveTestHelper* save2 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave2"];

    // Remove file and sync.
    [save2 syncAndWaitNoError];
    [save2 deleteFile:@"test1.save"];
    [save2 syncAndWaitNoError];

    // Check that the first manager has removed the file.
    [save1 syncAndWaitNoError];
    XCTAssertFalse([save1 fileExists:@"test1.save"]);
    [save1 checkFile:@"test2.save" withContent:@"content2"];
}

- (void) testFileChange {
    CloudSaveTestHelper* save1 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave1"];

    [save1 syncAndWaitNoError];
    [save1 createFile:@"test1.save" content:@"content1"];
    [save1 createFile:@"test2.save" content:@"content2"];
    [save1 syncAndWaitNoError];

    CloudSaveTestHelper* save2 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave2"];

    // Remove file and sync.
    [save2 syncAndWaitNoError];
    [save2 writeFile:@"test1.save" content:@"mynewcontent"];
    [save2 syncAndWaitNoError];

    [save1 syncAndWaitNoError];
    [save1 checkFile:@"test1.save" withContent:@"mynewcontent"];
    [save1 checkFile:@"test2.save" withContent:@"content2"];
}

- (void) testEmptyNoConflict {
    CloudSaveTestHelper* save1 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave1"];

    [save1 syncAndWaitNoError];
    [save1 createFile:@"test1.save" content:@"content1"];
    [save1 createFile:@"test2.save" content:@"content2"];
    [save1 syncAndWaitNoError];
    [save1 deleteFile:@"test1.save"];
    [save1 deleteFile:@"test2.save"];
    [save1 syncAndWaitNoError];

    // Expects no conflict.
    CloudSaveTestHelper* save2 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave2"];
    [save2 createFile:@"test1.save" content:@"content1"];
    [save2 createFile:@"test2.save" content:@"content2"];
    [save2 syncAndWaitNoError];

    [save1 syncAndWaitNoError];
    [save1 checkFile:@"test1.save" withContent:@"content1"];
    [save1 checkFile:@"test2.save" withContent:@"content2"];
}


- (void) testConflictResolveLocal {
    CloudSaveTestHelper* save1 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave1"];
    [save1 syncAndWaitNoError];

    CloudSaveTestHelper* save2 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave2"];
    [save2 syncAndWaitNoError];

    [save1 createFile:@"test1.save" content:@"save1_content1"];
    [save1 createFile:@"test2.save" content:@"save2_content1"];
    [save1 createFile:@"test4.save" content:@"save4_content1"];
    [save1 syncAndWaitNoError];

    [save2 createFile:@"test2.save" content:@"save2_content2"];
    [save2 createFile:@"test3.save" content:@"save3_content2"];
    [save2 syncAndWait:^(BOOL conflictDetected, NSError *error) {
        // Expect a conflict.
        XCTAssertTrue(conflictDetected);
        XCTAssertNil(error);
        XCTAssertNotNil(save2.manager.unresolvedConflict);
        XCTAssertEqual(save2.manager.unresolvedConflict.localSaveInformation.files.count, 2);
        XCTAssertEqual(save2.manager.unresolvedConflict.serverSaveInformation.files.count, 3);

        [save2 resolveAndWait:CloudSaveLocalityLocal completionHandler:^(BOOL otherConflictDetected, NSError *error) {
            XCTAssertFalse(otherConflictDetected);
            XCTAssertNil(error);
            XCTAssertNil(save2.manager.unresolvedConflict);

            // Verify that local changes resolve the conflict.
            [save2 checkFile:@"test2.save" withContent:@"save2_content2"];
            [save2 checkFile:@"test3.save" withContent:@"save3_content2"];
            XCTAssertFalse([save2 fileExists:@"test1.save"]);
            XCTAssertFalse([save2 fileExists:@"test4.save"]);
        }];
    }];

    // Sync again and check for the new state.
    [save1 syncAndWaitNoError];
    XCTAssertNil(save1.manager.unresolvedConflict);
    [save1 checkFile:@"test2.save" withContent:@"save2_content2"];
    [save1 checkFile:@"test3.save" withContent:@"save3_content2"];
    XCTAssertFalse([save1 fileExists:@"test1.save"]);
    XCTAssertFalse([save1 fileExists:@"test4.save"]);
}

- (void) testConflictResolveServer {
    CloudSaveTestHelper* save1 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave1"];
    [save1 syncAndWaitNoError];

    CloudSaveTestHelper* save2 = [[CloudSaveTestHelper alloc] initWithName:@"CloudSave2"];
    [save2 syncAndWaitNoError];

    [save1 createFile:@"test1.save" content:@"save1_content1"];
    [save1 createFile:@"test2.save" content:@"save2_content1"];
    [save1 createFile:@"test4.save" content:@"save4_content1"];
    [save1 syncAndWaitNoError];

    [save2 createFile:@"test2.save" content:@"save2_content2"];
    [save2 createFile:@"test3.save" content:@"save3_content2"];
    [save2 syncAndWait:^(BOOL conflictDetected, NSError *error) {
        // Expect a conflict.
        XCTAssertTrue(conflictDetected);
        XCTAssertNil(error);
        XCTAssertNotNil(save2.manager.unresolvedConflict);
        XCTAssertEqual(save2.manager.unresolvedConflict.localSaveInformation.files.count, 2);
        XCTAssertEqual(save2.manager.unresolvedConflict.serverSaveInformation.files.count, 3);

        [save2 resolveAndWait:CloudSaveLocalityServer completionHandler:^(BOOL otherConflictDetected, NSError *error) {
            XCTAssertFalse(otherConflictDetected);
            XCTAssertNil(error);
            XCTAssertNil(save2.manager.unresolvedConflict);

            // Verify that server changes resolve the conflict.
            [save2 checkFile:@"test1.save" withContent:@"save1_content1"];
            [save2 checkFile:@"test2.save" withContent:@"save2_content1"];
            [save2 checkFile:@"test4.save" withContent:@"save4_content1"];
            XCTAssertFalse([save2 fileExists:@"test3.save"]);
        }];
    }];

    // Sync again and check that the local state still exists.
    [save1 syncAndWaitNoError];
    [save1 checkFile:@"test1.save" withContent:@"save1_content1"];
    [save1 checkFile:@"test2.save" withContent:@"save2_content1"];
    [save1 checkFile:@"test4.save" withContent:@"save4_content1"];
    XCTAssertFalse([save1 fileExists:@"test3.save"]);
}



@end
