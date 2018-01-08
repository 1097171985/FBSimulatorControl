/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorBootVerificationStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceBootInfo.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorBootVerificationStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@interface FBSimulatorBootVerificationStrategy_LaunchCtlServices : FBSimulatorBootVerificationStrategy

@property (nonatomic, copy, readonly) NSArray<NSString *> *requiredServiceNames;

- (instancetype)initWithSimulator:(FBSimulator *)simulator requiredServiceNames:(NSArray<NSString *> *)requiredServiceNames;

+ (NSArray<NSString *> *)requiredLaunchdServicesToVerifyBooted:(FBSimulator *)simulator;

@end

@interface FBSimulatorBootVerificationStrategy_SimDeviceBootInfo : FBSimulatorBootVerificationStrategy

@end


@implementation FBSimulatorBootVerificationStrategy

#pragma mark Initializers

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
{
  if ([simulator.device respondsToSelector:@selector(bootStatus)]) {
    return [[FBSimulatorBootVerificationStrategy_SimDeviceBootInfo alloc] initWithSimulator:simulator];
  } else {
    NSArray<NSString *> *requiredServiceNames = [FBSimulatorBootVerificationStrategy_LaunchCtlServices requiredLaunchdServicesToVerifyBooted:simulator];
    return [[FBSimulatorBootVerificationStrategy_LaunchCtlServices alloc] initWithSimulator:simulator requiredServiceNames:requiredServiceNames];
  }
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark Public

static NSTimeInterval BootVerificationWaitInterval = 0.5;

- (FBFuture<NSNull *> *)verifySimulatorIsBooted
{
  FBSimulator *simulator = self.simulator;

  return [[simulator
    resolveState:FBSimulatorStateBooted]
    onQueue:simulator.workQueue fmap:^FBFuture *(NSNull *_) {
      return [FBFuture onQueue:simulator.workQueue resolveUntil:^{
        return [[self performBootVerification] delay:BootVerificationWaitInterval];
      }];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)performBootVerification
 {
   NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
   return nil;
 }

@end

@implementation FBSimulatorBootVerificationStrategy_SimDeviceBootInfo

- (FBFuture<NSNull *> *)performBootVerification
{
  SimDeviceBootInfo *bootInfo = self.simulator.device.bootStatus;
  if (!bootInfo) {
    return [[FBSimulatorError
      describeFormat:@"No bootStatus for %@", self.simulator]
      failFuture];
  }
  if (bootInfo.status != SimDeviceBootInfoStatusBooted) {
    return [[FBSimulatorError
      describeFormat:@"Not booted status is %@", bootInfo]
      failFuture];
  }
  return [FBFuture futureWithResult:NSNull.null];
}

@end

@implementation FBSimulatorBootVerificationStrategy_LaunchCtlServices

- (instancetype)initWithSimulator:(FBSimulator *)simulator requiredServiceNames:(NSArray<NSString *> *)requiredServiceNames
{
  self = [super initWithSimulator:simulator];
  if (!self) {
    return nil;
  }

  _requiredServiceNames = requiredServiceNames;

  return self;
}

- (FBFuture<NSNull *> *)performBootVerification
{
  return [[self.simulator
    listServices]
    onQueue:self.simulator.asyncQueue fmap:^(NSDictionary<NSString *, id> *services) {
      NSDictionary<id, NSString *> *processIdentifiers = [NSDictionary
        dictionaryWithObjects:self.requiredServiceNames
        forKeys:[services objectsForKeys:self.requiredServiceNames notFoundMarker:NSNull.null]];
      if (processIdentifiers[NSNull.null]) {
        return [[FBSimulatorError
          describeFormat:@"Service %@ has not started", processIdentifiers[NSNull.null]]
          failFuture];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

/*
 A Set of launchd_sim service names that are used to determine whether relevant System daemons are available after booting.

 There is a period of time between when CoreSimulator says that the Simulator is 'Booted'
 and when it is stable enough state to launch Applications/Daemons, these Service Names
 represent the Services that are known to signify readyness.

 @return the required Service Names.
 */
+ (NSArray<NSString *> *)requiredLaunchdServicesToVerifyBooted:(FBSimulator *)simulator
{
  FBControlCoreProductFamily family = simulator.productFamily;
  if (family == FBControlCoreProductFamilyiPhone || family == FBControlCoreProductFamilyiPad) {
    if (FBXcodeConfiguration.isXcode9OrGreater) {
      return @[
        @"com.apple.backboardd",
        @"com.apple.mobile.installd",
        @"com.apple.CoreSimulator.bridge",
        @"com.apple.SpringBoard",
      ];
    }
    if (FBXcodeConfiguration.isXcode8OrGreater ) {
      return @[
        @"com.apple.backboardd",
        @"com.apple.mobile.installd",
        @"com.apple.SimulatorBridge",
        @"com.apple.SpringBoard",
      ];
    }
  }
  if (family == FBControlCoreProductFamilyAppleWatch || family == FBControlCoreProductFamilyAppleTV) {
    if (FBXcodeConfiguration.isXcode8OrGreater) {
      return @[
        @"com.apple.mobileassetd",
        @"com.apple.nsurlsessiond",
      ];
    }
    return @[
      @"com.apple.mobileassetd",
      @"com.apple.networkd",
    ];
  }
  return @[];
}

@end
