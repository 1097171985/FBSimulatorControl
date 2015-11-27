/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorTerminationStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBCoreSimulatorNotifier.h"
#import "FBProcessQuery.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction.h"
#import "FBSimulatorLogger.h"
#import "FBSimulatorPredicates.h"
#import "FBProcessInfo.h"
#import "FBProcessQuery.h"
#import "FBTaskExecutor+Convenience.h"
#import "FBTaskExecutor.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

@interface FBSimulatorTerminationStrategy ()

@property (nonatomic, copy, readonly) FBSimulatorControlConfiguration *configuration;
@property (nonatomic, copy, readonly) NSArray *allSimulators;

@property (nonatomic, strong, readonly) FBProcessQuery *processQuery;

@end

@implementation FBSimulatorTerminationStrategy

+ (instancetype)usingKillOnConfiguration:(FBSimulatorControlConfiguration *)configuration allSimulators:(NSArray *)allSimulators
{
  return [[FBSimulatorTerminationStrategy alloc] initWithConfiguration:configuration allSimulators:allSimulators];
}

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration allSimulators:(NSArray *)allSimulators
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _allSimulators = allSimulators;
  _processQuery = [FBProcessQuery new];

  return self;
}

- (NSArray *)killAllWithError:(NSError **)error
{
  return [self killSimulators:self.allSimulators withError:error];
}

- (NSArray *)killSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSSet *udids = [NSSet setWithArray:[simulators valueForKey:@"udid"]];
  NSPredicate *predicate = [self simulatorWithOneOf:udids];

  NSError *innerError = nil;
  if (![self killSimulatorProcessesMatchingPredicate:predicate error:&innerError]) {
    return [[[FBSimulatorError describe:@"Could not kill simulators before shutting them down"] causedBy:innerError] fail:error];
  }
  if (![self safeShutdownSimulators:simulators withError:&innerError]) {
    return [[[FBSimulatorError describe:@"Could not shut down simulators after killing them"] causedBy:innerError] fail:error];
  }

  return simulators;
}

- (BOOL)killSpuriousSimulatorsWithError:(NSError **)error
{
  NSPredicate *predicate = [NSCompoundPredicate orPredicateWithSubpredicates:@[
    self.simulatorsFromDifferentXcodeVersionPredicate,
    self.simulatorsNotLaunchedBySimulatorControl
  ]];

  NSError *innerError = nil;
  if (![self killSimulatorProcessesMatchingPredicate:predicate error:&innerError]) {
    return [[[FBSimulatorError describe:@"Could not kill non-current spurious simulators"] causedBy:innerError] failBool:error];
  }
  return YES;
}

#pragma mark Private

- (NSPredicate *)simulatorsFromDifferentXcodeVersionPredicate
{
  // If it's from a different Xcode version, the binary path will be different.
  NSString *simulatorBinaryPath = self.configuration.simulatorApplication.binary.path;
  return [NSPredicate predicateWithBlock:^ BOOL (id<FBProcessInfo> process, NSDictionary *_) {
    return ![process.launchPath isEqualToString:simulatorBinaryPath];
  }];
}

- (NSPredicate *)simulatorsNotLaunchedBySimulatorControl
{
  // All Simulators launched by FBSimulatorControl have a magic string in their environment
  return [NSPredicate predicateWithBlock:^ BOOL (id<FBProcessInfo> process, NSDictionary *_) {
    NSSet *argumentSet = [NSSet setWithArray:process.environment.allKeys];
    return ![argumentSet containsObject:FBSimulatorControlSimulatorLaunchEnvironmentMagic];
  }];
}

- (NSPredicate *)simulatorWithOneOf:(NSSet *)udids
{
  return [NSPredicate predicateWithBlock:^ BOOL (id<FBProcessInfo> process, NSDictionary *_) {
    NSSet *argumentSet = [NSSet setWithArray:process.arguments];
    return [udids intersectsSet:argumentSet];
  }];
}

- (NSArray *)simulatorProcesses
{
  // All Simulator Versions from Xcode 5-7, have Simulator.app in their path.
  return [self.processQuery processesWithLaunchPathSubstring:@"Simulator.app"];
}

- (BOOL)killSimulatorProcessesMatchingPredicate:(NSPredicate *)predicate error:(NSError **)error
{
  NSArray *processes = [self.simulatorProcesses filteredArrayUsingPredicate:predicate];
  return [self killProcesses:processes error:error];
}

- (BOOL)killProcesses:(NSArray *)processes error:(NSError **)error
{
  for (id<FBProcessInfo> process in processes) {
    NSParameterAssert(process.processIdentifier > 1);
    if (kill(process.processIdentifier, SIGTERM) < 0) {
      return [[FBSimulatorError describeFormat:@"Failed to kill process %@", process] failBool:error];
    }
  }
  return YES;
}

- (NSArray *)safeShutdownSimulators:(NSArray *)simulators withError:(NSError **)error
{
  NSError *innerError = nil;
  for (FBSimulator *simulator in simulators) {
    if (![self safeShutdown:simulator withError:&innerError]) {
      return [FBSimulatorError failWithError:innerError errorOut:error];
    }
  }
  return simulators;
}

- (BOOL)safeShutdown:(FBSimulator *)simulator withError:(NSError **)error
{
  // Calling shutdown when already shutdown should be avoided (if detected).
  if (simulator.state == FBSimulatorStateShutdown) {
    return YES;
  }

  // Code 159 (Xcode 7) or 146 (Xcode 6) is 'Unable to shutdown device in current state: Shutdown'
  // We can safely ignore this and then confirm that the simulator is shutdown
  NSError *innerError = nil;
  if (![simulator.device shutdownWithError:&innerError] && innerError.code != 159 && innerError.code != 146) {
    return [FBSimulatorError failBoolWithError:innerError description:@"Simulator could not be shutdown" errorOut:error];
  }

  // We rely on the catch-all-non-manged kill command to do the dirty work.
  // This will confirm that all these simulators are shutdown.
  return [simulator waitOnState:FBSimulatorStateShutdown withError:error];
}

@end
