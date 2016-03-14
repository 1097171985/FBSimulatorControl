/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestManager.h"

#import "FBDeviceOperator.h"
#import "FBTestManagerAPIMediator.h"

@interface FBTestManager () <FBTestManagerMediatorDelegate>
@property (nonatomic, strong) FBTestManagerAPIMediator *mediator;
@property (nonatomic, strong) id<FBDeviceOperator> deviceOperator;
@end

@implementation FBTestManager

+ (instancetype)testManagerWithOperator:(id<FBDeviceOperator>)deviceOperator testRunnerPID:(pid_t)testRunnerPID sessionIdentifier:(NSUUID *)sessionIdentifier
{
  FBTestManager *testManager = [self.class new];
  testManager.mediator = [FBTestManagerAPIMediator mediatorWithDevice:deviceOperator.dvtDevice testRunnerPID:testRunnerPID sessionIdentifier:sessionIdentifier];
  testManager.mediator.delegate = testManager;
  testManager.deviceOperator = deviceOperator;
  return testManager;
}

- (BOOL)connectWithError:(NSError *__autoreleasing *)error
{
  [self.mediator connectTestRunnerWithTestManagerDaemon];
  return YES;
}

#pragma mark - FBTestManagerMediatorDelegate

- (BOOL)testManagerMediator:(FBTestManagerAPIMediator *)mediator launchProcessWithPath:(NSString *)path bundleID:(NSString *)bundleID arguments:(NSArray *)arguments environmentVariables:(NSDictionary *)environment error:(NSError **)error
{
  if (![self.deviceOperator isApplicationInstalledWithBundleID:bundleID error:error]) {
    if (![self.deviceOperator installApplicationWithPath:path error:error]) {
      return NO;
    }
  }
  if (![self.deviceOperator launchApplicationWithBundleID:bundleID arguments:arguments environment:environment error:error]) {
    return NO;
  }
  return YES;
}

@end
