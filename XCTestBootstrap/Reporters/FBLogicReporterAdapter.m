/**
 * Copyright (c) 2017-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBLogicReporterAdapter.h"
#import <XCTestBootstrap/FBXCTestReporter.h>
#import <XCTestBootstrap/FBXCTestLogger.h>

@interface FBLogicReporterAdapter ()

@property (nonatomic, readonly) id<FBXCTestReporter> reporter;
@property (nonatomic, readonly) FBXCTestLogger *logger;

@end

@implementation FBLogicReporterAdapter

- (instancetype)initWithReporter:(id<FBXCTestReporter>)reporter
{
  self = [self init];
  if (!self) {
    return nil;
  }
  _reporter = reporter;
  _logger = [FBXCTestLogger defaultLoggerInDefaultDirectory];

  return self;
}

- (void)debuggerAttached
{
  [self.reporter debuggerAttached];
}

- (void)didBeginExecutingTestPlan
{
  [self.reporter didBeginExecutingTestPlan];
}

- (void)didFinishExecutingTestPlan
{
  [self.reporter didFinishExecutingTestPlan];
}

- (void)processWaitingForDebuggerWithProcessIdentifier:(pid_t)pid
{
  [self.reporter processWaitingForDebuggerWithProcessIdentifier:pid];
}

- (void)testHadOutput:(NSString *)output
{
  [self.reporter testHadOutput:output];
}

- (void)handleEventJSONData:(NSData *)data
{
  NSError *error;
  NSDictionary<NSString *, id> *JSONEvent = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error || ![JSONEvent isKindOfClass:[NSDictionary class]]) {
    [self.logger logFormat:@"[%@] Received invalid JSON: %@",
     NSStringFromClass(self.class),
     [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
    return;
  }
  NSString *eventName = JSONEvent[@"event"];
  id<FBXCTestReporter> reporter = self.reporter;

  if ([eventName isEqualToString:@"begin-test-suite"]) {
    NSString *suite = JSONEvent[@"suite"];
    NSString *startTime = JSONEvent[@"timestamp"];

    [reporter testSuite:suite didStartAt:startTime];
  } else if ([eventName isEqualToString:@"begin-test"]) {
    NSString *testClass = JSONEvent[@"className"];
    NSString *testName = JSONEvent[@"methodName"];

    [reporter testCaseDidStartForTestClass:testClass method:testName];
  } else if ([eventName isEqualToString:@"end-test"]) {
    NSString *testClass = JSONEvent[@"className"];
    NSString *testName = JSONEvent[@"methodName"];
    NSString *result = JSONEvent[@"result"];
    NSTimeInterval duration = [JSONEvent[@"totalDuration"] doubleValue];
    FBTestReportStatus status;
    if ([result isEqualToString:@"success"]) {
      status = FBTestReportStatusPassed;
    } else if ([result isEqualToString:@"failure"]) {
      NSDictionary *exception = [JSONEvent[@"exceptions"] lastObject];
      NSString *message = exception[@"reason"];
      NSString *file = exception[@"filePathInProject"];
      NSInteger line = [exception[@"lineNumber"] integerValue];
      [reporter testCaseDidFailForTestClass:testClass method:testName withMessage:message file:file line:(NSUInteger)line];
      status = FBTestReportStatusFailed;
    } else {
      status = FBTestReportStatusUnknown;
    }
    [reporter testCaseDidFinishForTestClass:testClass method:testName withStatus:status duration:duration];
  } else {
    [self.logger logFormat:@"[%@] Unhandled event JSON: %@", NSStringFromClass(self.class), JSONEvent];
  }
}

@end
