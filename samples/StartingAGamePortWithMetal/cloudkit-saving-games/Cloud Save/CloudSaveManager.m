/*
<samplecode>
  <abstract>
  Implementation of the class that manages syncing saves with iCloud.
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

#import <os/log.h>

#import <TargetConditionals.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#import <CloudKit/CKContainer.h>
#import <CloudKit/CKDatabase.h>
#import <CloudKit/CKRecordZone.h>
#import <CloudKit/CKRecordID.h>
#import <CloudKit/CKModifyRecordsOperation.h>
#import <CloudKit/CKModifyRecordZonesOperation.h>
#import <CloudKit/CKFetchRecordZoneChangesOperation.h>
#import <CloudKit/CKError.h>
#import <CloudKit/CKQuery.h>
#import <CloudKit/CKQueryOperation.h>

#import "CloudSaveManager.h"

static NSString* kLastModificationDateRecordKey = @"lastModificationDate";
static NSString* kFileRecordKey = @"file";
static NSString* kDeviceNameRecordKey = @"deviceName";
static NSString* kSaveFileRecordType = @"SaveFile";
static NSString* kRootRecordType = @"RootRecord";
static NSString* kRootRecordName = @"/RootRecord";
static NSString* kCloudRecordZoneName = @"SaveGameFiles";
static NSString* kDefaultStateFileName = @"SaveState.db";

os_log_t CloudSaveLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.apple.cloudsave", "CloudSave");
    });
    return log;
}

typedef struct CloudRecordChanges {
    CKServerChangeToken* serverChangeToken;
    CKRecord* rootRecord;
    NSMutableArray<CKRecord*>* changedRecords;
    NSMutableArray<CKRecordID*>* deletedRecords;
} CloudRecordChanges;

static NSString* GetCurrentDeviceName(void)
{
#if TARGET_OS_OSX
    return [[NSHost currentHost] localizedName];
#else
    return [[UIDevice currentDevice] name];
#endif
}

@interface CloudSaveDeviceInformation ()
@property(readwrite) CloudSaveLocality locality;
@property(readwrite) NSString* deviceName;
@property(readwrite) NSArray<NSString*>* files;
@property(readwrite) NSDate* lastFileModification;
@end

@implementation CloudSaveDeviceInformation
@synthesize locality;
@synthesize deviceName;
@synthesize files;
@synthesize lastFileModification;
@end

@interface CloudSaveConflict ()
@property(readwrite) CloudSaveDeviceInformation* localSaveInformation;
@property(readwrite) CloudSaveDeviceInformation* serverSaveInformation;
@property(readwrite) NSArray<CKRecord*>* serverRecords;
@property(readwrite) CKRecord* serverRootRecord;
@end

@implementation CloudSaveConflict
@synthesize localSaveInformation;
@synthesize serverSaveInformation;
@end

typedef enum CloudSaveFileState : NSInteger {
    CloudSaveFileStateUpToDate = 0,
    CloudSaveFileStatePendingUpload = 1,
    CloudSaveFileStatePendingDelete = 2
} CloudSaveFileState;

// `CloudSaveFile` abstracts `CKRecord` creation and serialization to disk.
@interface CloudSaveFile : NSObject<NSSecureCoding>
@property CloudSaveFileState state;
@property NSString* relativePath;
@property CKRecord* record;
@end

@implementation CloudSaveFile

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:_state forKey:@"state"];
    [coder encodeObject:_relativePath forKey:@"relativePath"];
    [_record encodeSystemFieldsWithCoder:coder];
    [coder encodeObject:_record[kLastModificationDateRecordKey] forKey:@"lastModificationDate"];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        _state = [coder decodeIntegerForKey:@"state"];
        _relativePath = [coder decodeObjectOfClass:[NSString class] forKey:@"relativePath"];
        _record = [[CKRecord alloc] initWithCoder:coder];
        _record[kLastModificationDateRecordKey] = [coder decodeObjectOfClass:[NSDate class] forKey:@"lastModificationDate"];
    }
    return self;
}

- (nullable instancetype) initWithURL:(NSURL*) url zoneID:(CKRecordZoneID *)zoneID {
    self = [super init];
    if (self) {
        CKRecordID* recordID = [[CKRecordID alloc] initWithRecordName:url.relativePath zoneID:zoneID];
        _record = [[CKRecord alloc] initWithRecordType:kSaveFileRecordType recordID:recordID];

        NSDate* lastModificationDate = [NSDate now];
        [url getResourceValue:&lastModificationDate forKey:NSURLContentModificationDateKey error:nil];

        _record[kLastModificationDateRecordKey] = lastModificationDate;

        _state = CloudSaveFileStatePendingUpload;
        _relativePath = url.relativePath;
    }
    return self;
}

- (nullable instancetype) initWithRemoteRecord:(CKRecord*) record {
    self = [super init];
    if (self) {
        _record = record;
        _relativePath = record.recordID.recordName;
        _state = CloudSaveFileStateUpToDate;
    }
    return self;
}

// After fetching a record from the server, merge it with a local file.
- (BOOL) moveFromRemoteRecord:(CKRecord*) record saveDirectory:(NSURL*) saveDirectory {

    CKAsset* fileAsset = record[kFileRecordKey];
    NSDate* lastModificationDate = record[kLastModificationDateRecordKey];

    NSURL* destinationURL = [NSURL fileURLWithPath:record.recordID.recordName relativeToURL:saveDirectory];

    NSURL* destinationURLDir = destinationURL.URLByDeletingLastPathComponent;

    [[NSFileManager defaultManager] createDirectoryAtURL:destinationURLDir withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];

    NSError* error;
    if (![[NSFileManager defaultManager] moveItemAtURL:fileAsset.fileURL toURL:destinationURL error:&error])
    {
        os_log_error(CloudSaveLog(), "Could not move file: %@", error);
        return NO;
    }

    [destinationURL setResourceValue:lastModificationDate forKey:NSURLContentModificationDateKey error:nil];

    _record = record;
    _relativePath = record.recordID.recordName;
    os_log_debug(CloudSaveLog(), "%@: file merged from remote", _relativePath);
    return YES;
}


// Create a `CKRecord` so that it's ready to upload to iCloud.
// Optionally, stage the file so that you can modify it afterward without interupting the operation.
- (BOOL) prepareForUpload:(NSURL*) saveDirectory
              withStaging:(BOOL) staging
                    error:(NSError**) error {

    NSURL* fileURL = [NSURL fileURLWithPath:_relativePath relativeToURL:saveDirectory];

    if (staging) {
        NSURL* tempDirectory = [[NSFileManager defaultManager] temporaryDirectory];
        NSURL* stagingURL = [NSURL fileURLWithPath:[[NSUUID UUID] UUIDString] relativeToURL:tempDirectory];

        if (![[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:stagingURL error:error])
            return NO;

        _record[kFileRecordKey] = [[CKAsset alloc] initWithFileURL:stagingURL];
    } else {
        _record[kFileRecordKey] = [[CKAsset alloc] initWithFileURL:fileURL];
    }

    return YES;
}

- (void)setLastModificationDate:(NSDate*)lastModificationDate {
    _record[kLastModificationDateRecordKey] = lastModificationDate;
}

- (NSDate*)lastModificationDate {
    return _record[kLastModificationDateRecordKey];
}

+ (BOOL)supportsSecureCoding {
  return YES;
}

@end

// `CloudSaveManagerState` abstracts the current state of the client.
// It detects file changes and only updates records that have changed.
@interface CloudSaveManagerState : NSObject<NSSecureCoding>
@property BOOL conflictPending;
@property CKServerChangeToken* lastServerChangeToken;
@property CKRecord* rootRecord;
@property NSMutableDictionary<NSString*, CloudSaveFile*>* localFiles;
@end

@implementation CloudSaveManagerState

- (void)encodeWithCoder:(NSCoder *)coder  {
    [coder encodeBool:_conflictPending forKey:@"conflictPending"];
    [coder encodeObject:_lastServerChangeToken forKey:@"lastServerChangeToken"];
    [coder encodeObject:_localFiles forKey:@"localFiles"];
    [_rootRecord encodeSystemFieldsWithCoder:coder];
}

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super init];
    if (self) {
        _conflictPending = [coder decodeBoolForKey:@"conflictPending"];
        _lastServerChangeToken = [coder decodeObjectOfClass:[CKServerChangeToken class] forKey:@"lastServerChangeToken"];
        _localFiles = [coder decodeObjectOfClasses:[NSSet setWithArray:@[[NSMutableDictionary class],
                                                                         [NSString class],
                                                                         [CloudSaveFile class]]]
                                            forKey:@"localFiles"];

        _rootRecord = [[CKRecord alloc] initWithCoder:coder];
    }
    return self;
}

- (instancetype) init {
    self = [super init];
    if (self) {
        _localFiles = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
  return YES;
}

@end

@interface CloudSaveManager()
@property CloudSaveManagerState* state;
@property CloudSaveConflict* unresolvedConflict;
@end

@implementation CloudSaveManager
{
    CKContainer* _cloudContainer;
    CKDatabase* _cloudDatabase;

    CKRecordZone* _cloudRecordZone;
    CKModifyRecordZonesOperation* _cloudRecordZoneOperation;

    NSURL* _databaseURL;

    CloudSaveConflict* _unresolvedConflict;

    dispatch_semaphore_t _operationInProgress;
}

- (instancetype) initWithCloudIdentifier:(NSString*) identifier
                        saveDirectoryURL:(NSURL*) saveDirectoryURL
                                  filter:(NSPredicate*) predicate
                             databaseURL:(NSURL*) databaseURL {
    self = [super init];

    if (self) {
        [self loadStateFromDisk:databaseURL];

        _saveDirectory = saveDirectoryURL;
        _saveDirectoryFilter = predicate;
        _operationInProgress = dispatch_semaphore_create(1);

        _cloudContainer = [CKContainer containerWithIdentifier:identifier];
        _cloudDatabase = _cloudContainer.privateCloudDatabase;
        _cloudRecordZone = [[CKRecordZone alloc] initWithZoneName:kCloudRecordZoneName];

        // Start an operation to create the record zone.
        _cloudRecordZoneOperation = [[CKModifyRecordZonesOperation alloc] init];
        _cloudRecordZoneOperation.qualityOfService = NSQualityOfServiceUserInteractive;
        _cloudRecordZoneOperation.recordZonesToSave = @[_cloudRecordZone];
        _cloudRecordZoneOperation.modifyRecordZonesCompletionBlock = ^(NSArray<CKRecordZone *> * savedRecordZones,
                                                                       NSArray<CKRecordZoneID *> * deletedRecordZoneIDs,
                                                                       NSError* operationError) {
            if (operationError)
                os_log_error(CloudSaveLog(), "Could not create zone: %@", operationError);
        };
        [_cloudDatabase addOperation:_cloudRecordZoneOperation];

        [[NSFileManager defaultManager] createDirectoryAtURL:_saveDirectory
                                 withIntermediateDirectories:YES
                                                  attributes:nil error:nil];
    }

    return self;
}

- (instancetype) initWithCloudIdentifier:(NSString*) identifier
                        saveDirectoryURL:(NSURL*) saveDirectoryURL
{
    return [self initWithCloudIdentifier:identifier
                        saveDirectoryURL:saveDirectoryURL
                                  filter:[NSPredicate predicateWithValue:YES]
                             databaseURL:[NSURL URLWithString:kDefaultStateFileName relativeToURL:saveDirectoryURL]];
}

// Load `CloudSaveManagerState` from a file from the disk holding the previous state of the client.
- (void) loadStateFromDisk:(NSURL*) url {
    _state = nil;
    _databaseURL = url;

    NSData* data = [NSData dataWithContentsOfURL:url];
    if (data) {
        NSError* error;
        _state = [NSKeyedUnarchiver unarchivedObjectOfClass:[CloudSaveManagerState class]
                                                   fromData:data
                                                      error:&error];
        if (error)
            os_log_error(CloudSaveLog(), "Could not load state from file: %@", error);
    }

    if (!_state) {
        _state = [[CloudSaveManagerState alloc] init];
    }
}

- (void) saveStateToDisk {
    NSError* error;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:_state
                                         requiringSecureCoding:YES
                                                         error:&error];
    if (data)
        [data writeToURL:_databaseURL options:0 error:&error];

    if (error)
        os_log_error(CloudSaveLog(), "Could not write state to file: %@", error);
}

// Filter saves according to the predicate specified at initialization so that only those files are saved.
// Ensure that the file for the state itself is not being saved.
- (NSArray<NSURL*>*) filteredSaveFiles {

    NSMutableArray<NSURL*>* filteredUrls = [NSMutableArray array];

    NSDirectoryEnumerator<NSURL *>* urls = [[NSFileManager defaultManager] enumeratorAtURL:_saveDirectory
                                                                includingPropertiesForKeys:@[NSURLContentModificationDateKey]
                                                                                   options:NSDirectoryEnumerationProducesRelativePathURLs
                                                                              errorHandler:nil];

    for (NSURL* url in urls) {
        // Filter out the state file.
        if ([url.absoluteString isEqualToString:_databaseURL.absoluteString])
            continue;

        if (!url.hasDirectoryPath) {
            if ([_saveDirectoryFilter evaluateWithObject:url]) {
                [filteredUrls addObject:url];
            }
        }
    }
    return filteredUrls;
}

// Compare the database and local files.
// If new or deleted local files exist, assume that those have been modified offline and mark them for update.
- (void) detectFileChanges {
    NSArray<NSURL*>* filteredURLs = [self filteredSaveFiles];
    NSMutableDictionary<NSString*, NSURL*>* filteredURLsDict = [NSMutableDictionary dictionaryWithCapacity:filteredURLs.count];

    // Create dictionary for convenience.
    for (NSURL* url in filteredURLs) {
        filteredURLsDict[url.relativePath] = url;
    }

    [_state.localFiles enumerateKeysAndObjectsUsingBlock:^(NSString* key, CloudSaveFile* save, BOOL* stop) {
        NSURL* url = [filteredURLsDict objectForKey:key];
        if (url)
        {
            NSDate *lastModificationDate;
            if ([url getResourceValue:&lastModificationDate forKey:NSURLContentModificationDateKey error:nil]) {
                if ([lastModificationDate compare:save.lastModificationDate] != NSOrderedSame) {
                    // Dates don't match - update local file.
                    save.lastModificationDate = lastModificationDate;
                    save.state = CloudSaveFileStatePendingUpload;
                    os_log_debug(CloudSaveLog(), "%@: offline change detected", save.relativePath);
                }
            }
        }
        else
        {
            // If it doesn't exit in the list of local files, assume it's up for deletion.
            save.state = CloudSaveFileStatePendingDelete;
            os_log_debug(CloudSaveLog(), "%@: offline deletion detected", save.relativePath);
        }
    }];

    // Find whether there are files that are only present locally.
    for (NSURL* url in filteredURLs) {
        id save = [_state.localFiles objectForKey:url.relativePath];
        if (!save) {
            CloudSaveFile* newSave = [[CloudSaveFile alloc] initWithURL:url zoneID:_cloudRecordZone.zoneID];
            _state.localFiles[url.relativePath] = newSave;
            os_log_debug(CloudSaveLog(), "%@: offline addition detected", newSave.relativePath);
        }
    }

    [self saveStateToDisk];
}

// Maintain a root record to easily find save information during a conflict.
// Root record also allows you to force a conflict when two devices modify unrelated files.
- (void) updateLocalRootRecord {
    __block NSUInteger fileCountAfterSync = 0;
    __block NSDate* latestModificationDate = nil;
    [_state.localFiles enumerateKeysAndObjectsUsingBlock:^(NSString* key, CloudSaveFile* save, BOOL* stop) {
        if (latestModificationDate == nil || [save.lastModificationDate laterDate:latestModificationDate]) {
            latestModificationDate = save.lastModificationDate;
         }

        if (save.state != CloudSaveFileStatePendingDelete)
            ++fileCountAfterSync;
    }];

    // If no files remain after the sync, delete the root record to avoid creating needless conflicts.
    if (fileCountAfterSync == 0) {
        _state.rootRecord = nil;
        return;
    }

    if (!_state.rootRecord) {
        CKRecordID* recordID = [[CKRecordID alloc] initWithRecordName:kRootRecordName zoneID:_cloudRecordZone.zoneID];
        _state.rootRecord = [[CKRecord alloc] initWithRecordType:kRootRecordType recordID:recordID];
    }

    _state.rootRecord[kDeviceNameRecordKey] = GetCurrentDeviceName();
    _state.rootRecord[kLastModificationDateRecordKey] = latestModificationDate;
}

// Send the files marked for update to the server.
// This will generate a conflict when someone has modified records since last fetch.
- (void) sendChangesWithCompletionHandler:(void (^)(BOOL conflictDetected, NSError * error)) completionHandler withStaging:(BOOL)staging {
    NSMutableArray<CKRecord*>* recordsToSave = [NSMutableArray array];
    NSMutableArray<CKRecordID*>* recordsToDelete = [NSMutableArray array];

    __block int conflictCount = 0;
    __block int errorCount = 0;

    [_state.localFiles enumerateKeysAndObjectsUsingBlock:^(NSString* key, CloudSaveFile* save, BOOL* stop) {
        NSError* error = nil;
        if (save.state == CloudSaveFileStatePendingUpload) {
            if ([save prepareForUpload:_saveDirectory
                           withStaging:staging
                                 error:&error]) {
                [recordsToSave addObject:save.record];
                os_log_debug(CloudSaveLog(), "%@: file will be uploaded", save.relativePath);
            }
        } 

        if (save.state == CloudSaveFileStatePendingDelete) {
            [recordsToDelete addObject:save.record.recordID];
            os_log_debug(CloudSaveLog(), "%@: file will be deleted", save.relativePath);
        }
    }];

    os_log_debug(CloudSaveLog(), "Sending %lu additions and %lu deletions", recordsToSave.count, recordsToDelete.count);

    if (recordsToSave.count == 0 && recordsToDelete.count == 0)
    {
        completionHandler(NO, nil);
        return;
    }

    [self updateLocalRootRecord];

    if (_state.rootRecord)
        [recordsToSave addObject:_state.rootRecord];
    else // After deleting all files, remove the root record to prevent new changes from generating a conflict.
        [recordsToDelete addObject:[[CKRecordID alloc] initWithRecordName:kRootRecordName zoneID:_cloudRecordZone.zoneID]];

    CKModifyRecordsOperation * modifyRecord = [[CKModifyRecordsOperation alloc] initWithRecordsToSave:recordsToSave
                                                                                    recordIDsToDelete:recordsToDelete];

    modifyRecord.atomic = YES;
    modifyRecord.qualityOfService = NSQualityOfServiceUserInteractive;
    modifyRecord.perRecordSaveBlock = ^(CKRecordID *recordID, CKRecord* record, NSError* error) {
        if (error.code == CKErrorServerRecordChanged)
        {
            ++conflictCount;
        } else if (error) {
            ++errorCount;
            os_log_error(CloudSaveLog(), "Could not save record: %@", error);
        } else {
            if ([record.recordType isEqual: kSaveFileRecordType]) {
                CloudSaveFile* save = [self.state.localFiles objectForKey:recordID.recordName];
                if (save)
                    save.state = CloudSaveFileStateUpToDate;
            }
        }
    };

    modifyRecord.perRecordDeleteBlock =  ^(CKRecordID *recordID, NSError* error) {
        if (error.code == CKErrorServerRecordChanged)
        {
            ++conflictCount;
        } else if (error) {
            ++errorCount;
            os_log_error(CloudSaveLog(), "Could not delete record: %@", error);
        } else {
            [self.state.localFiles removeObjectForKey:recordID.recordName];
        }
    };

    modifyRecord.modifyRecordsCompletionBlock = ^(NSArray<CKRecord*>* savedRecords, 
                                                  NSArray<CKRecordID*>* deletedRecordIDs,
                                                  NSError* operationError) {

        if (operationError && errorCount != 0)
            os_log_error(CloudSaveLog(), "Could not modify records: %@", operationError);

        self.state.conflictPending = conflictCount > 0;
        [self saveStateToDisk];
        completionHandler(self.state.conflictPending, errorCount != 0 ? operationError : nil);
    };

    // Ensure zone creation is complete.
    [modifyRecord addDependency:_cloudRecordZoneOperation];

    [_cloudDatabase addOperation:modifyRecord];
}

// Create device information for conflict resolution using the root record.
+ (CloudSaveDeviceInformation*) createDeviceInformation:(CKRecord*) rootRecord
                                            fileRecords:(NSArray<CKRecord*>*) fileRecords
                                               locality:(CloudSaveLocality)locality {
    CloudSaveDeviceInformation* info = [[CloudSaveDeviceInformation alloc] init];
    info.locality = locality;
    info.lastFileModification = rootRecord[kLastModificationDateRecordKey];
    info.deviceName = rootRecord[kDeviceNameRecordKey];

    NSMutableArray<NSString*>* files = [NSMutableArray arrayWithCapacity:fileRecords.count];
    for (CKRecord* record in fileRecords) {
        [files addObject:record.recordID.recordName];
    }
    info.files = files;
    return info;
}

// Create information necessary for the user to resolve the conflict using local and server records.
- (void) createConflictWithServerRecord:(NSArray<CKRecord*>*) serverRecords {
    NSMutableArray<CKRecord*>* serverRecordFiles = [NSMutableArray arrayWithCapacity:serverRecords.count];
    CKRecord* serverRootRecord = nil;

    for (CKRecord* record in serverRecords) {
        if ([record.recordType isEqual: kSaveFileRecordType]) {
            [serverRecordFiles addObject:record];
        } else if ([record.recordType isEqual: kRootRecordType]) {
            serverRootRecord = record;
        }
    }

    NSMutableArray<CKRecord*>* localRecordFiles = [NSMutableArray arrayWithCapacity:_state.localFiles.count];
    [_state.localFiles enumerateKeysAndObjectsUsingBlock:^(NSString* key, CloudSaveFile* save, BOOL* stop) {
        [localRecordFiles addObject:save.record];
    }];

    CloudSaveConflict* conflict = [[CloudSaveConflict alloc] init];

    conflict.serverSaveInformation = [CloudSaveManager createDeviceInformation:serverRootRecord fileRecords:serverRecordFiles locality:CloudSaveLocalityServer];
    conflict.localSaveInformation = [CloudSaveManager createDeviceInformation:_state.rootRecord fileRecords:localRecordFiles locality:CloudSaveLocalityLocal];
    conflict.serverRecords = serverRecordFiles;
    conflict.serverRootRecord = serverRootRecord;
    _unresolvedConflict = conflict;
}

// Fetch records from the server that will help resolve the detected conflict.
- (void) fetchConflictsWithCompletionHandler:(void (^)(NSError * error)) completionHandler {
    CKFetchRecordZoneChangesOperation* fetchRecord = [[CKFetchRecordZoneChangesOperation alloc] init];
    CKFetchRecordZoneChangesConfiguration* zoneConfig = [[CKFetchRecordZoneChangesConfiguration alloc] init];

    zoneConfig.desiredKeys = @[ kDeviceNameRecordKey, kLastModificationDateRecordKey ];
    zoneConfig.previousServerChangeToken = nil; // Force getting changes for all records.

    fetchRecord.qualityOfService = NSQualityOfServiceUserInteractive;
    fetchRecord.fetchAllChanges = YES;
    fetchRecord.recordZoneIDs = @[_cloudRecordZone.zoneID];
    fetchRecord.configurationsByRecordZoneID = @{ _cloudRecordZone.zoneID: zoneConfig };

    NSMutableArray<CKRecord*>* serverRecords = [NSMutableArray array];

    fetchRecord.recordWasChangedBlock = ^(CKRecordID *recordID, CKRecord *record, NSError *error) {
        if (error)
            os_log_error(CloudSaveLog(), "Could not fetch record: %@", error);
        else
            [serverRecords addObject:record];
    };

    fetchRecord.fetchRecordZoneChangesCompletionBlock = ^(NSError* operationError) {
        if (!operationError)
            [self createConflictWithServerRecord:serverRecords];
        completionHandler(operationError);
    };

    // Ensure zone creation is complete.
    [fetchRecord addDependency:_cloudRecordZoneOperation];

    [_cloudDatabase addOperation:fetchRecord];
}

- (void) onConflictDetected:(void (^)(BOOL conflictDetected, NSError * error)) finishSync {
    [self fetchConflictsWithCompletionHandler:^(NSError *error) {
        finishSync(YES, error);
    }];
}

// Use a server token to fetch records from the server that someone has modified since the last fetch.
- (void) fetchChangesWithCompletionHandler:(void (^)(CloudRecordChanges* changes, NSError * error)) completionHandler {

    CKFetchRecordZoneChangesOperation* fetchRecord = [[CKFetchRecordZoneChangesOperation alloc] init];
    CKFetchRecordZoneChangesConfiguration* zoneConfig = [[CKFetchRecordZoneChangesConfiguration alloc] init];

    zoneConfig.previousServerChangeToken = _state.lastServerChangeToken;

    fetchRecord.qualityOfService = NSQualityOfServiceUserInteractive;
    fetchRecord.fetchAllChanges = YES;
    fetchRecord.recordZoneIDs = @[_cloudRecordZone.zoneID];
    fetchRecord.configurationsByRecordZoneID = @{ _cloudRecordZone.zoneID: zoneConfig };

    __block CloudRecordChanges changes;
    changes.serverChangeToken = nil;
    changes.rootRecord = nil;
    changes.changedRecords = [NSMutableArray array];
    changes.deletedRecords = [NSMutableArray array];

    __block NSError* recordZoneError = nil;

    fetchRecord.recordWasChangedBlock = ^(CKRecordID *recordID, CKRecord *record, NSError *error) {
        if (error) {
            os_log_error(CloudSaveLog(), "Could not fetch changed record: %@", error);
        } else if ([record.recordType isEqual: kRootRecordType]) {
            changes.rootRecord = record;
        } else {
            [changes.changedRecords addObject:record];
        }
    };

    fetchRecord.recordWithIDWasDeletedBlock = ^(CKRecordID *recordID, CKRecordType recordType) {
        [changes.deletedRecords addObject:recordID];
    };

    fetchRecord.recordZoneFetchCompletionBlock = ^(CKRecordZoneID* recordZoneID, CKServerChangeToken* serverChangeToken, NSData* clientChangeTokenData, BOOL moreComing, NSError * error) {
        changes.serverChangeToken = serverChangeToken;
        recordZoneError = error;
    };

    fetchRecord.fetchRecordZoneChangesCompletionBlock = ^(NSError* operationError) {
        if (operationError) {
            os_log_error(CloudSaveLog(), "Could not fetch records: %@", operationError);
            completionHandler(nil, recordZoneError ? recordZoneError : operationError);
        } else {
            completionHandler(&changes, nil);
        }
    };

    // Ensure zone creation is complete.
    [fetchRecord addDependency:_cloudRecordZoneOperation];

    [_cloudDatabase addOperation:fetchRecord];
}

- (void) fetchAndMergeWithCompletionHandler:(void (^)(NSError * error)) finishFetch {
    [self fetchChangesWithCompletionHandler:^(CloudRecordChanges* changes, NSError *error) {
        if (!error)
            [self mergeRecordChangesFromServer:changes];
        finishFetch(error);
    }];
}

- (void) syncWithCompletionHandler:(void (^)(BOOL conflictDetected, NSError * error)) finishSync fetch:(BOOL) fetch {
    [self detectFileChanges];

    [self sendChangesWithCompletionHandler:^(BOOL conflictDetected, NSError *error) {
        if (conflictDetected) {
            [self onConflictDetected:finishSync];
        } else if (error) {
            finishSync(NO, error);
        } else if (fetch) {
            [self fetchAndMergeWithCompletionHandler:^(NSError *error) {
                if (error && error.code == CKErrorChangeTokenExpired) {
                    os_log_debug(CloudSaveLog(), "Change token has expired, reset state");
                    self.state = [[CloudSaveManagerState alloc] init];
                    [self syncWithCompletionHandler:finishSync fetch:YES];
                } else {
                    finishSync(NO, error);
                }
            }];
        } else {
            finishSync(NO, error);
        }
    } withStaging:fetch ? NO : YES];
}

- (void) syncWithCompletionHandler:(void (^)(BOOL conflictDetected, NSError * error)) finishSync {
    dispatch_semaphore_wait(self->_operationInProgress, DISPATCH_TIME_FOREVER);
    [self syncWithCompletionHandler:^(BOOL conflictDetected, NSError * error) {
        dispatch_semaphore_signal(self->_operationInProgress);
        finishSync(conflictDetected, error);
    } fetch:YES];
}


- (void) uploadWithCompletionHandler:(void (^)(BOOL conflictDetected, NSError * error)) finishUpload {
    dispatch_semaphore_wait(self->_operationInProgress, DISPATCH_TIME_FOREVER);

    [self syncWithCompletionHandler:^(BOOL conflictDetected, NSError * error) {
        dispatch_semaphore_signal(self->_operationInProgress);
        finishUpload(conflictDetected, error);
    } fetch:NO];
}

// Review all the record changes you fetched from the server, merge them with the local one, and update local files appropriately.
- (void) mergeRecordChangesFromServer:(CloudRecordChanges*) changes {
    if (changes->rootRecord)
        _state.rootRecord = changes->rootRecord;

    NSUInteger saveFileChanged = 0;
    for (CKRecord* record in changes->changedRecords) {
        NSString* recordName = record.recordID.recordName;

        CloudSaveFile* save = [self.state.localFiles objectForKey:recordName];
        if (!save) {
            CloudSaveFile* save = [[CloudSaveFile alloc] initWithRemoteRecord:record];
            if ([save moveFromRemoteRecord:record saveDirectory:_saveDirectory])
                self.state.localFiles[recordName] = save;
        } else {
            if (save.record.recordChangeTag != record.recordChangeTag)
                [save moveFromRemoteRecord:record saveDirectory:_saveDirectory];
        }

        ++saveFileChanged;
    }

    for (CKRecordID* recordID in changes->deletedRecords) {
        NSURL* destinationURL = [NSURL fileURLWithPath:recordID.recordName relativeToURL:_saveDirectory];
        NSError* error;

        if ([self.state.localFiles objectForKey:recordID.recordName]) {
            if (![[NSFileManager defaultManager] removeItemAtURL:destinationURL error:&error]) {
                os_log_error(CloudSaveLog(), "Could not delete local file: %@", error);
            }
            os_log_debug(CloudSaveLog(), "%@: local file deleted", recordID.recordName);
            [self.state.localFiles removeObjectForKey:recordID.recordName];
        }
    }

    self.state.lastServerChangeToken = changes->serverChangeToken;
    [self saveStateToDisk];

    os_log_debug(CloudSaveLog(), "Fetched %lu additions and %lu deletions", saveFileChanged, changes->deletedRecords.count);
}

// Remove all the files you're tracking locally and erase the local state to allow for a clean fetch, typically after a conflict resolution.
- (void) eraseLocalFiles
{
	_state.lastServerChangeToken = nil;
	[_state.localFiles enumerateKeysAndObjectsUsingBlock:^(NSString* key, CloudSaveFile* save, BOOL* stop) {
		NSError* error;
		NSURL* destinationURL = [NSURL fileURLWithPath:save.record.recordID.recordName relativeToURL:_saveDirectory];
		if (![[NSFileManager defaultManager] removeItemAtURL:destinationURL error:&error]) {
			os_log_error(CloudSaveLog(), "Could not delete local file: %@", error);
		}
	}];
	[_state.localFiles removeAllObjects];
	_state.conflictPending = NO;
	_state.rootRecord = nil;
	[self saveStateToDisk];
}

- (void) resolveToLocalFilesWithCompletionHandler:(void (^)(BOOL otherConflictDetected, NSError *))completionHandler {
    for (CKRecord* serverRecord in _unresolvedConflict.serverRecords) {
        NSString* recordName = serverRecord.recordID.recordName;
        CloudSaveFile* save = [self.state.localFiles objectForKey:recordName];
        if (save) {
            CKRecord* oldRecord = save.record;
            serverRecord[kLastModificationDateRecordKey] = oldRecord[kLastModificationDateRecordKey];
            save.record = serverRecord;
            save.state = CloudSaveFileStatePendingUpload;
        } else {
            CloudSaveFile* save = [[CloudSaveFile alloc] initWithRemoteRecord:serverRecord];
            save.state = CloudSaveFileStatePendingDelete;
            self.state.localFiles[recordName] = save;
        }
    }

    _state.rootRecord = _unresolvedConflict.serverRootRecord;
    self.unresolvedConflict = nil;

    [self sendChangesWithCompletionHandler:^(BOOL conflictDetected, NSError *error) {
        if (conflictDetected) {
            [self onConflictDetected:completionHandler];
        } else {
            completionHandler(conflictDetected, error);
        }
    } withStaging:NO];
}

// When you resolve from the server, remove all of the local state and fetch everything again.
- (void) resolveToServerFilesWithCompletionHandler:(void (^)(BOOL otherConflictDetected, NSError *))completionHandler {
    _state.lastServerChangeToken = nil;

    [self fetchChangesWithCompletionHandler:^(CloudRecordChanges* changes, NSError *error) {
        if (error) {
            completionHandler(NO, error);
        } else {
            // Verify that no new conflict exists.
            if (changes->rootRecord.recordChangeTag == self.unresolvedConflict.serverRootRecord.recordChangeTag) {
                [self eraseLocalFiles];
                self.unresolvedConflict = nil;
                [self mergeRecordChangesFromServer:changes];
                completionHandler(NO, nil);
            } else {
                [self onConflictDetected:completionHandler];
            }
        }
    }];
}

- (void)resolveConflictWithLocality:(CloudSaveLocality)locality
                  completionHandler:(void (^)(BOOL otherConflictDetected, NSError *))completionHandler {

    dispatch_semaphore_wait(self->_operationInProgress, DISPATCH_TIME_FOREVER);

    if (locality == CloudSaveLocalityLocal) {
        [self resolveToLocalFilesWithCompletionHandler:^(BOOL otherConflictDetected, NSError * error) {
            dispatch_semaphore_signal(self->_operationInProgress);
            completionHandler(otherConflictDetected, error);
        }];
    }

    if (locality == CloudSaveLocalityServer) {
        [self resolveToServerFilesWithCompletionHandler:^(BOOL otherConflictDetected, NSError * error) {
            dispatch_semaphore_signal(self->_operationInProgress);
            completionHandler(otherConflictDetected, error);
        }];
    }
}

@end
