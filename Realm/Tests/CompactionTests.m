////////////////////////////////////////////////////////////////////////////
//
// Copyright 2017 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

#import "RLMTestCase.h"

@interface RLMRealm ()
- (BOOL)compact;
@end

@interface CompactionTests : RLMTestCase
@end

@implementation CompactionTests

#pragma mark - Expected Sizes

// Note: These exact numbers are very sensitive to changes in core's allocator
// and other internals unrelated to what this is testing, but it's probably useful
// to know if they ever change, so it's preferable to have the test fail if these
// exact numbers fluctuate.
NSUInteger expectedTotalBytesBefore = 655360;
NSUInteger expectedUsedBytesBefore = 70144;
NSUInteger expectedTotalBytesAfter = 73728;
NSUInteger count = 1000;

#pragma mark - Helpers

- (unsigned long long)fileSize:(NSURL *)fileURL {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:nil];
    return [(NSNumber *)attributes[NSFileSize] unsignedLongLongValue];
}

- (void)setUp {
    [super setUp];
    @autoreleasepool {
        // Make compactable Realm
        RLMRealm *realm = self.realmWithTestPath;
        NSString *uuid = [[NSUUID UUID] UUIDString];
        [realm transactionWithBlock:^{
            [StringObject createInRealm:realm withValue:@[@"A"]];
            for (NSUInteger i = 0; i < count; ++i) {
                [StringObject createInRealm:realm withValue:@[uuid]];
            }
            [StringObject createInRealm:realm withValue:@[@"B"]];
        }];
    }
}

#pragma mark - Tests

- (void)testCompact {
    RLMRealm *realm = self.realmWithTestPath;
    unsigned long long fileSizeBefore = [self fileSize:realm.configuration.fileURL];
    StringObject *object = [StringObject allObjectsInRealm:realm].firstObject;

    XCTAssertTrue([realm compact]);

    XCTAssertTrue(object.isInvalidated);
    XCTAssertEqual([[StringObject allObjectsInRealm:realm] count], count + 2);
    XCTAssertEqualObjects(@"A", [[StringObject allObjectsInRealm:realm].firstObject stringCol]);
    XCTAssertEqualObjects(@"B", [[StringObject allObjectsInRealm:realm].lastObject stringCol]);

    unsigned long long fileSizeAfter = [self fileSize:realm.configuration.fileURL];
    XCTAssertGreaterThan(fileSizeBefore, fileSizeAfter);
}

- (void)testSuccessfulCompactOnLaunch {
    // Configure the Realm to compact on launch
    RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
    configuration.fileURL = RLMTestRealmURL();
    configuration.shouldCompactOnLaunchBlock = ^BOOL(NSUInteger totalBytes, NSUInteger usedBytes){
        // Confirm expected sizes
        XCTAssertEqual(totalBytes, expectedTotalBytesBefore);
        XCTAssertEqual(usedBytes, expectedUsedBytesBefore);

        // Compact if the file is over 500KB in size and less than 20% 'used'
        // In practice, users might want to use values closer to 100MB and 50%
        NSUInteger fiveHundredKB = 500 * 1024;
        return (totalBytes > fiveHundredKB) && (usedBytes / totalBytes) < 0.2;
    };

    // Confirm expected sizes before and after opening the Realm
    XCTAssertEqual([self fileSize:configuration.fileURL], expectedTotalBytesBefore);
    RLMRealm *realm = [RLMRealm realmWithConfiguration:configuration error:nil];
    XCTAssertEqual([self fileSize:configuration.fileURL], expectedTotalBytesAfter);

    // Validate that the file still contains what it should
    XCTAssertEqual([[StringObject allObjectsInRealm:realm] count], count + 2);
    XCTAssertEqualObjects(@"A", [[StringObject allObjectsInRealm:realm].firstObject stringCol]);
    XCTAssertEqualObjects(@"B", [[StringObject allObjectsInRealm:realm].lastObject stringCol]);
}

- (void)testNoBlockCompactOnLaunch {
    // Configure the Realm to compact on launch
    RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
    configuration.fileURL = RLMTestRealmURL();
    // Confirm expected sizes before and after opening the Realm
    XCTAssertEqual([self fileSize:configuration.fileURL], expectedTotalBytesBefore);
    RLMRealm *realm = [RLMRealm realmWithConfiguration:configuration error:nil];
    XCTAssertEqual([self fileSize:configuration.fileURL], expectedTotalBytesBefore);

    // Validate that the file still contains what it should
    XCTAssertEqual([[StringObject allObjectsInRealm:realm] count], count + 2);
    XCTAssertEqualObjects(@"A", [[StringObject allObjectsInRealm:realm].firstObject stringCol]);
    XCTAssertEqualObjects(@"B", [[StringObject allObjectsInRealm:realm].lastObject stringCol]);
}

- (void)testCachedRealmCompactOnLaunch {
    // Test that compact never gets called if there are cached Realms
    // Access Realm before opening it with a compaction block
    RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
    configuration.fileURL = RLMTestRealmURL();
    __unused RLMRealm *firstRealm = [RLMRealm realmWithConfiguration:configuration error:nil];

    // Configure the Realm to compact on launch
    RLMRealmConfiguration *configurationWithCompactBlock = [configuration copy];
    configurationWithCompactBlock.shouldCompactOnLaunchBlock = ^BOOL(NSUInteger totalBytes, NSUInteger usedBytes){
        // Confirm expected sizes
        XCTAssertEqual(totalBytes, expectedTotalBytesBefore);
        XCTAssertEqual(usedBytes, expectedUsedBytesBefore);

        // Always attempt to compact
        return YES;
    };

    // Confirm expected sizes before and after opening the Realm
    XCTAssertEqual([self fileSize:configuration.fileURL], expectedTotalBytesBefore);
    RLMRealm *realm = [RLMRealm realmWithConfiguration:configurationWithCompactBlock error:nil];
    XCTAssertEqual([self fileSize:configuration.fileURL], expectedTotalBytesBefore);

    // Validate that the file still contains what it should
    XCTAssertEqual([[StringObject allObjectsInRealm:realm] count], count + 2);
    XCTAssertEqualObjects(@"A", [[StringObject allObjectsInRealm:realm].firstObject stringCol]);
    XCTAssertEqualObjects(@"B", [[StringObject allObjectsInRealm:realm].lastObject stringCol]);
}

- (void)testReturnNoCompactOnLaunch {
    // Configure the Realm to compact on launch
    RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
    configuration.fileURL = RLMTestRealmURL();
    configuration.shouldCompactOnLaunchBlock = ^BOOL(NSUInteger totalBytes, NSUInteger usedBytes){
        // Confirm expected sizes
        XCTAssertEqual(totalBytes, expectedTotalBytesBefore);
        XCTAssertEqual(usedBytes, expectedUsedBytesBefore);
        // Don't compact.
        return NO;
    };
    // Confirm expected sizes before and after opening the Realm
    XCTAssertEqual([self fileSize:configuration.fileURL], expectedTotalBytesBefore);
    RLMRealm *realm = [RLMRealm realmWithConfiguration:configuration error:nil];
    XCTAssertEqual([self fileSize:configuration.fileURL], expectedTotalBytesBefore);

    // Validate that the file still contains what it should
    XCTAssertEqual([[StringObject allObjectsInRealm:realm] count], count + 2);
    XCTAssertEqualObjects(@"A", [[StringObject allObjectsInRealm:realm].firstObject stringCol]);
    XCTAssertEqualObjects(@"B", [[StringObject allObjectsInRealm:realm].lastObject stringCol]);
}

// TODO: Write docs
// TODO: Add Swift tests
// TODO: Add Object Store tests
// TODO: Validate that you can only set a block for writable, on-disk, non-synced Realms

@end
