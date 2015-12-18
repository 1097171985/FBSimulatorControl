/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControl+Class.h"

#import <CoreSimulator/SimDevice.h>

#import <DVTFoundation/DVTPlatform.h>

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlStaticConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorHistory.h"
#import "FBSimulatorLogger.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSession+Convenience.h"
#import "FBSimulatorSession.h"

@implementation FBSimulatorControl

#pragma mark - Initializers

+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration logger:(id<FBSimulatorLogger>)logger error:(NSError **)error
{
  if (![FBSimulatorControl doGlobalPreconditionsWithError:error]) {
    return nil;
  }

  logger = logger ?: FBSimulatorControlStaticConfiguration.defaultLogger;
  return [[FBSimulatorControl alloc] initWithConfiguration:configuration logger:logger error:error];
}

+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration error:(NSError **)error
{
  return [self withConfiguration:configuration logger:nil error:error];
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration logger:(id<FBSimulatorLogger>)logger error:(NSError **)error
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _simulatorPool = [FBSimulatorPool poolWithConfiguration:configuration logger:logger error:error];
  return self;
}

#pragma mark - Public Methods

- (FBSimulatorSession *)createSessionForSimulatorConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration options:(FBSimulatorAllocationOptions)options error:(NSError **)error;
{
  NSParameterAssert(simulatorConfiguration);

  NSError *innerError = nil;
  FBSimulator *simulator = [self.simulatorPool allocateSimulatorWithConfiguration:simulatorConfiguration options:options error:&innerError];
  if (!simulator) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  return [FBSimulatorSession sessionWithSimulator:simulator];
}

#pragma mark - Private Methods

+ (BOOL)doGlobalPreconditionsWithError:(NSError **)error
{
  static BOOL hasRunOnce = NO;
  if (!hasRunOnce) {
    return YES;
  }

  FBSetSimulatorLoggingEnabled(FBSimulatorControlStaticConfiguration.simulatorDebugLoggingEnabled);

  NSError *innerError = nil;
  if (![DVTPlatform loadAllPlatformsReturningError:&innerError]) {
    return [[[FBSimulatorError describe:@"Failed to Load all platforms"] causedBy:innerError] failBool:error];
  }
  return YES;
}

@end
