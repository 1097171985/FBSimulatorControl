/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestProcess.h"

#import <sys/wait.h>

#import <FBControlCore/FBControlCore.h>

#import "XCTestBootstrapError.h"
#import "FBXCTestProcessExecutor.h"

static NSTimeInterval const CrashLogStartDateFuzz = -20;
static NSTimeInterval const CrashLogWaitTime = 20;

@interface FBXCTestProcess() <FBLaunchedProcess>

@end

@implementation FBXCTestProcess

@synthesize processIdentifier = _processIdentifier;
@synthesize exitCode = _exitCode;

#pragma mark Initializers

- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier exitCode:(FBFuture<NSNumber *> *)exitCode
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processIdentifier = processIdentifier;
  _exitCode = exitCode;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"xctest Process %d | State %@", self.processIdentifier, self.exitCode];
}

#pragma mark NSObject

#pragma mark Public

+ (FBFuture<id<FBLaunchedProcess>> *)startWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutConsumer:(id<FBFileConsumer>)stdOutConsumer stdErrConsumer:(id<FBFileConsumer>)stdErrConsumer executor:(id<FBXCTestProcessExecutor>)executor timeout:(NSTimeInterval)timeout
{
  [FBCrashLogNotifier startListening];
  NSDate *startDate = [NSDate.date dateByAddingTimeInterval:CrashLogStartDateFuzz];

  return [[executor
    startProcessWithLaunchPath:launchPath arguments:arguments environment:environment stdOutConsumer:stdOutConsumer stdErrConsumer:stdErrConsumer]
    onQueue:executor.workQueue map:^(id<FBLaunchedProcess> processInfo) {
      FBFuture<NSNumber *> *exitCode = [FBXCTestProcess decorateLaunchedWithErrorHandlingProcess:processInfo startDate:startDate timeout:timeout queue:executor.workQueue];
      return [[FBXCTestProcess alloc] initWithProcessIdentifier:processInfo.processIdentifier exitCode:exitCode];
    }];
}

#pragma mark Private

+ (FBFuture<NSNumber *> *)decorateLaunchedWithErrorHandlingProcess:(id<FBLaunchedProcess>)processInfo startDate:(NSDate *)startDate timeout:(NSTimeInterval)timeout queue:(dispatch_queue_t)queue
{
  FBFuture<NSNumber *> *completionFuture = [processInfo.exitCode
    onQueue:queue fmap:^(NSNumber *exitCode) {
      return [FBXCTestProcess onQueue:queue confirmNormalExitFor:processInfo.processIdentifier exitCode:exitCode.intValue startDate:startDate];
    }];
  FBFuture<NSNumber *> *timeoutFuture = [FBXCTestProcess onQueue:queue timeoutFuture:timeout processIdentifier:processInfo.processIdentifier];
  return [FBFuture race:@[completionFuture, timeoutFuture]];
}

+ (FBFuture<NSNumber *> *)onQueue:(dispatch_queue_t)queue timeoutFuture:(NSTimeInterval)timeout processIdentifier:(pid_t)processIdentifier
{
  return [[FBFuture
    futureWithDelay:timeout future:[FBFuture futureWithResult:NSNull.null]]
    onQueue:queue fmap:^(id _) {
      return [FBXCTestProcess onQueue:queue timeoutErrorWithTimeout:timeout processIdentifier:processIdentifier];
    }];
}

+ (FBFuture<id> *)onQueue:(dispatch_queue_t)queue timeoutErrorWithTimeout:(NSTimeInterval)timeout processIdentifier:(pid_t)processIdentifier
{
  return [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/sample" arguments:@[@(processIdentifier).stringValue, @"1"]]
    runUntilCompletion]
    onQueue:queue fmap:^(FBTask *task) {
      return [[FBXCTestError
        describeFormat:@"Waited %f seconds for process %d to terminate, but the xctest process stalled: %@", timeout, processIdentifier, task.stdOut]
        failFuture];
    }];
}

+ (FBFuture<NSNumber *> *)onQueue:(dispatch_queue_t)queue confirmNormalExitFor:(pid_t)processIdentifier exitCode:(int)exitCode startDate:(NSDate *)startDate
{
  // If exited abnormally, check for a crash log
  if (exitCode == 0 || exitCode == 1) {
    return [FBFuture futureWithResult:@(exitCode)];
  }
  return [[[FBXCTestProcess
    onQueue:queue crashLogsForTerminationOfProcess:processIdentifier since:startDate]
    rephraseFailure:@"xctest process (%d) exited abnormally (exit code %d) with no crash log", processIdentifier, exitCode]
    onQueue:queue fmap:^(FBCrashLogInfo *crashInfo) {
      FBDiagnostic *diagnosticCrash = [crashInfo toDiagnostic:FBDiagnosticBuilder.builder];
      return [[FBXCTestError
        describeFormat:@"xctest process crashed\n %@", diagnosticCrash.asString]
        failFuture];
    }];
}

+ (FBFuture<FBCrashLogInfo *> *)onQueue:(dispatch_queue_t)queue crashLogsForTerminationOfProcess:(pid_t)processIdentifier since:(NSDate *)sinceDate
{
  return [[FBCrashLogNotifier
    nextCrashLogForProcessIdentifier:processIdentifier]
    timeout:CrashLogWaitTime waitingFor:@"Crash logs for terminated process %d to appear", processIdentifier];
}

@end
