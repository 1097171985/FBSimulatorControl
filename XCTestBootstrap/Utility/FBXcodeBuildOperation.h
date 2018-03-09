/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTestLaunchConfiguration;

@protocol FBiOSTarget;

/**
 An Xcode Build Operation.
 */
@interface FBXcodeBuildOperation : NSObject <FBiOSTargetContinuation>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param target the target to build an operation for.
 @param configuration the configuration to use.
 @param xcodeBuildPath the path to xcodebuild.
 @param testRunFilePath the path to the xcodebuild.xctestrun file
 @return a build operation.
 */
+ (instancetype)operationWithTarget:(id<FBiOSTarget>)target configuration:(FBTestLaunchConfiguration *)configuration xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath;

#pragma mark Public Methods

/**
 The xctest.xctestrun properties for a test launch.

 @param testLaunch the test launch to base off.
 @return the xctest.xctestrun properties.
 */
+ (NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *)xctestRunProperties:(FBTestLaunchConfiguration *)testLaunch;

/**
 Terminates all reparented xcodebuild processes.

 @param udid the udid of the target.
 @param processFetcher the process fetcher to use.
 @param queue the termination queue
 @param logger a logger to log to.
 @return a Future that resolves when processes have exited.
 */
+ (FBFuture<NSArray<FBProcessInfo *> *> *)terminateAbandonedXcodebuildProcessesForUDID:(NSString *)udid processFetcher:(FBProcessFetcher *)processFetcher queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
