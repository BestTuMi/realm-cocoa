////////////////////////////////////////////////////////////////////////////
//
// Copyright 2016 Realm Inc.
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

#import "RLMRealmConfiguration+Sync.h"

#import "RLMRealmConfiguration_Private.hpp"

#import "RLMUser_Private.h"
#import "RLMSyncFileManager.hpp"
#import "RLMUtil.hpp"

typedef void(^SyncLoginBlock)(const std::string&);

@implementation RLMRealmConfiguration (Sync)

- (void)setErrorHandler:(RLMErrorReportingBlock)errorHandler {
    RLMErrorReportingBlock callback = (errorHandler ?: ^(NSError *) { });

    auto handler = [=](int error_code, std::string message) {
        NSString *nativeMessage = @(message.c_str());
        NSError *error = [NSError errorWithDomain:@"io.realm.sync.client"
                                             code:error_code
                                         userInfo:@{@"description": nativeMessage}];
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(error);
        });
    };
    self.config.sync_error_handler = handler;
}

- (void)setSyncPath:(RLMSyncPath)path
        forSyncUser:(RLMUser *)user {
    [self setSyncPath:path forSyncUser:user onCompletion:nil];
}

- (void)setSyncPath:(RLMSyncPath)path
        forSyncUser:(RLMUser *)user
       onCompletion:(nullable RLMErrorReportingBlock)completion {
    if (!path) {
        // Clear the sync state. User must explicitly set a file URL or in-memory identifier.
        self.config.sync_user_id = realm::util::none;
        self.config.sync_login_function = nullptr;
        self.fileURL = nil;
        self.inMemoryIdentifier = nil;
        return;
    }
    if (!user) {
        @throw RLMException(@"If a sync path is being set on a configuration, a valid user must also be specified.");
    }
    if (!user.isLoggedIn) {
        @throw RLMException(@"A configuration may only be configured with a logged-in user.");
    }
    // Set the sync server URL and associated state
    NSURL *syncServerURL = [NSURL URLWithString:path relativeToURL:user.syncURL];
    self.config.sync_user_id = std::string([user.identity UTF8String]);
    self.config.sync_login_function = [user, syncServerURL, completion](const std::string& fileURL) {
        [user _bindRealmWithLocalFileURL:fileURL remoteSyncURL:syncServerURL onCompletion:completion];
    };

    // Set the file URL
    NSURL *fileURL = [RLMSyncFileManager filePathForSyncServerURL:syncServerURL user:user];
    self.config.path = std::string([[fileURL path] UTF8String]);
    self.config.in_memory = false;
}

@end
