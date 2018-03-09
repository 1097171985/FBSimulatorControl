/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXcodeBuildOperation.h"

#import <FBControlCore/FBControlCore.h>

static NSString *XcodebuildEnvironmentTargetUDID = @"XCTESTBOOTSTRAP_TARGET_UDID";

@interface FBXcodeBuildOperation ()

@property (nonatomic, strong, readonly) FBFuture<FBTask *> *future;
@property (nonatomic, strong, readonly) dispatch_queue_t asyncQueue;

@end

@implementation FBXcodeBuildOperation

+ (instancetype)operationWithTarget:(id<FBiOSTarget>)target configuration:(FBTestLaunchConfiguration *)configuraton xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath
{
  FBFuture<FBTask *> *future = [self createTaskFuture:configuraton xcodeBuildPath:xcodeBuildPath testRunFilePath:testRunFilePath target:target];
  return [[self alloc] initWithFuture:future asyncQueue:target.asyncQueue];
}

+ (FBFuture<FBTask *> *)createTaskFuture:(FBTestLaunchConfiguration *)configuraton xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath target:(id<FBiOSTarget>)target
{
  NSMutableArray<NSString *> *arguments = [[NSMutableArray alloc] init];
  [arguments addObjectsFromArray:@[
    @"test-without-building",
    @"-xctestrun", testRunFilePath,
    @"-destination", [NSString stringWithFormat:@"id=%@", target.udid],
  ]];

  if (configuraton.resultBundlePath) {
    [arguments addObjectsFromArray:@[
      @"-resultBundlePath",
      configuraton.resultBundlePath,
    ]];
  }

  for (NSString *test in configuraton.testsToRun) {
    [arguments addObject:[NSString stringWithFormat:@"-only-testing:%@", test]];
  }

  for (NSString *test in configuraton.testsToSkip) {
    [arguments addObject:[NSString stringWithFormat:@"-skip-testing:%@", test]];
  }

  NSMutableDictionary<NSString *, NSString *> *environment = [NSProcessInfo.processInfo.environment mutableCopy];
  environment[XcodebuildEnvironmentTargetUDID] = target.udid;

  [target.logger logFormat:@"Running test with xcodebuild %@", [arguments componentsJoinedByString:@" "]];
  return [[[[[FBTaskBuilder
    withLaunchPath:xcodeBuildPath arguments:arguments]
    withEnvironment:environment]
    withStdOutToLogger:target.logger]
    withStdErrToLogger:target.logger]
    runUntilCompletion];
}

- (instancetype)initWithFuture:(FBFuture<FBTask *> *)future asyncQueue:(dispatch_queue_t)asyncQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _future = future;
  _asyncQueue = asyncQueue;

  return self;
}

#pragma mark FBiOSTargetContinuation

- (FBFuture<NSNull *> *)completed
{
  return [self.future mapReplace:NSNull.null];
}

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeTestOperation;
}

#pragma mark Public

+ (NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *)xctestRunProperties:(FBTestLaunchConfiguration *)testLaunch
{
  return @{
    @"StubBundleId" : @{
      @"TestHostPath" : testLaunch.testHostPath,
      @"TestBundlePath" : testLaunch.testBundlePath,
      @"UseUITargetAppProvidedByTests" : @YES,
      @"IsUITestBundle" : @YES,
      @"CommandLineArguments": testLaunch.applicationLaunchConfiguration.arguments,
      @"EnvironmentVariables": testLaunch.applicationLaunchConfiguration.environment,
      @"TestingEnvironmentVariables": @{
        @"DYLD_FRAMEWORK_PATH": @"__TESTROOT__:__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
        @"DYLD_LIBRARY_PATH": @"__TESTROOT__:__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
      },
    }
  };
}

+ (FBFuture<NSArray<FBProcessInfo *> *> *)terminateAbandonedXcodebuildProcessesForUDID:(NSString *)udid processFetcher:(FBProcessFetcher *)processFetcher queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSArray<FBProcessInfo *> *processes = [self activeXcodebuildProcessesForUDID:udid processFetcher:processFetcher];
  if (processes.count == 0) {
    [logger logFormat:@"No processes for %@ to terminate", udid];
    return [FBFuture futureWithResult:@[]];
  }
  [logger logFormat:@"Terminating abandoned xcodebuild processes %@", [FBCollectionInformation oneLineDescriptionFromArray:processes]];
  FBProcessTerminationStrategy *strategy = [FBProcessTerminationStrategy strategyWithProcessFetcher:processFetcher workQueue:queue logger:logger];
  NSMutableArray<FBFuture<FBProcessInfo *> *> *futures = [NSMutableArray array];
  for (FBProcessInfo *process in processes) {
    FBFuture<FBProcessInfo *> *termination = [[strategy killProcess:process] mapReplace:process];
    [futures addObject:termination];
  }
  return [FBFuture futureWithFutures:futures];
}

#pragma mark Private

+ (NSArray<FBProcessInfo *> *)activeXcodebuildProcessesForUDID:(NSString *)udid processFetcher:(FBProcessFetcher *)processFetcher
{
  NSArray<FBProcessInfo *> *xcodebuildProcesses = [processFetcher processesWithProcessName:@"xcodebuild"];
  NSMutableArray<FBProcessInfo *> *relevantProcesses = [NSMutableArray array];
  for (FBProcessInfo *process in xcodebuildProcesses) {
    if (![process.environment[XcodebuildEnvironmentTargetUDID] isEqualToString:udid]) {
      continue;
    }
    [relevantProcesses addObject:process];
  }
  return relevantProcesses;
}

@end
