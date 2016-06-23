/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlOperator.h"

#import <CoreSimulator/SimDevice.h>

#import <DTXConnectionServices/DTXSocketTransport.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import <sys/socket.h>
#import <sys/un.h>

#import <XCTestBootstrap/FBProductBundle.h>

#import "FBSimulatorError.h"

@interface FBSimulatorControlOperator ()
@property (nonatomic, strong) FBSimulator *simulator;
@end

@implementation FBSimulatorControlOperator

+ (instancetype)operatorWithSimulator:(FBSimulator *)simulator
{
  FBSimulatorControlOperator *operator = [self.class new];
  operator.simulator = simulator;
  return operator;
}


#pragma mark - FBDeviceOperator protocol

- (DTXTransport *)makeTransportForTestManagerServiceWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if ([NSThread isMainThread]) {
    return
    [[[FBSimulatorError
       describe:@"'makeTransportForTestManagerService' method may block and should not be called on the main thread"]
      logger:logger]
     fail:error];
  }

  const BOOL simulatorIsBooted = (self.simulator.device.state == 0x3);
  if (!simulatorIsBooted) {
    return
    [[[FBSimulatorError
       describe:@"Simulator should be already booted"]
      logger:logger]
     fail:error];
  }

  int testManagerSocketFD = socket(AF_UNIX, SOCK_STREAM, 0);
  if (testManagerSocketFD == -1) {
    return
    [[[FBSimulatorError
       describe:@"Unable to create a unix domain socket"]
      logger:logger]
     fail:error];
  }

  NSString *testManagerSocketString = [self testConnectionSocketPathWithLogger:logger];
  if(testManagerSocketString.length == 0) {
    return
    [[[FBSimulatorError
       describe:@"Failed to retrieve testmanagerd socket path"]
      logger:logger]
     fail:error];
  }

  if(![[NSFileManager new] fileExistsAtPath:testManagerSocketString]) {
    return
    [[[FBSimulatorError
       describeFormat:@"Simulator indicated unix domain socket for testmanagerd at path %@, but no file was found at that path.", testManagerSocketString]
      logger:logger]
     fail:error];
  }

  const char *testManagerSocketPath = testManagerSocketString.UTF8String;
  if(strlen(testManagerSocketPath) >= 0x68) {
    return
    [[[FBSimulatorError
       describeFormat:@"Unix domain socket path for simulator testmanagerd service '%s' is too big to fit in sockaddr_un.sun_path", testManagerSocketPath]
      logger:logger]
     fail:error];
  }

  struct sockaddr_un remote;
  remote.sun_family = AF_UNIX;
  strcpy(remote.sun_path, testManagerSocketPath);
  socklen_t length = (socklen_t)(strlen(remote.sun_path) + sizeof(remote.sun_family) + sizeof(remote.sun_len));
  if (connect(testManagerSocketFD, (struct sockaddr *)&remote, length) == -1) {
    return
    [[[FBSimulatorError
       describe:@"Failed to connect to testmangerd socket"]
      logger:logger]
     fail:error];
  }

  DTXSocketTransport *transport = [[NSClassFromString(@"DTXSocketTransport") alloc] initWithConnectedSocket:testManagerSocketFD disconnectAction:^{
    [logger logFormat:@"Disconnected socket %@", testManagerSocketString];
  }];
  return transport;
}

- (NSString *)testConnectionSocketPathWithLogger:(id<FBControlCoreLogger>)logger
{
  const NSUInteger maxTryCount = 10;
  NSUInteger tryCount = 0;
  do {
    NSString *socketPath = [self.simulator.device getenv:@"TESTMANAGERD_SIM_SOCK" error:nil];
    if (socketPath.length > 0) {
      return socketPath;
    }
    [logger logFormat:@"Simulator is booted but getenv returned nil for test connection socket path.\n Will retry in 1s (%lu attempts so far).", (unsigned long)tryCount];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
  } while (tryCount++ >= maxTryCount);
  return nil;
}

- (BOOL)requiresTestDaemonMediationForTestHostConnection
{
  return YES;
}

- (BOOL)waitForDeviceToBecomeAvailableWithError:(NSError **)error
{
  return YES;
}

- (BOOL)installApplicationWithPath:(NSString *)path error:(NSError **)error
{
  FBSimulatorApplication *application = [FBSimulatorApplication applicationWithPath:path error:error];
  if (![[self.simulator.interact installApplication:application] perform:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)isApplicationInstalledWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return ([self.simulator installedApplicationWithBundleID:bundleID error:error] != nil);
}

- (FBProductBundle *)applicationBundleWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  FBSimulatorApplication *application = [self.simulator installedApplicationWithBundleID:bundleID error:error];
  if (!application) {
    return nil;
  }

  FBProductBundle *productBundle =
  [[[FBProductBundleBuilder builder]
    withBundlePath:application.path]
   build];

  return productBundle;
}

- (BOOL)launchApplicationWithBundleID:(NSString *)bundleID arguments:(NSArray *)arguments environment:(NSDictionary *)environment error:(NSError **)error
{
  FBSimulatorApplication *app = [self.simulator installedApplicationWithBundleID:bundleID error:error];
  if (!app) {
    return NO;
  }

  FBApplicationLaunchConfiguration *configuration = [FBApplicationLaunchConfiguration new];
  configuration.bundleName = app.binary.name;
  configuration.bundleID = bundleID;
  configuration.arguments = arguments;
  configuration.environment = environment;

  if (![[self.simulator.interact launchOrRelaunchApplication:configuration] perform:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)killApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return [[self.simulator.interact terminateApplicationWithBundleID:bundleID] perform:error];
}

- (pid_t)processIDWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  FBSimulatorApplication *app = [self.simulator installedApplicationWithBundleID:bundleID error:error];
  return [[FBProcessFetcher new] subprocessOf:self.simulator.launchdProcess.processIdentifier withName:app.binary.name];
}


#pragma mark - Unsupported FBDeviceOperator protocol method

- (BOOL)cleanApplicationStateWithBundleIdentifier:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(nil, @"cleanApplicationStateWithBundleIdentifier is not yet supported");
  return NO;
}

- (NSString *)applicationPathForApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(nil, @"applicationPathForApplicationWithBundleID is not yet supported");
  return nil;
}

- (BOOL)uploadApplicationDataAtPath:(NSString *)path bundleID:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(nil, @"uploadApplicationDataAtPath is not yet supported");
  return NO;
}

- (NSString *)containerPathForApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(nil, @"containerPathForApplicationWithBundleID is not yet supported");
  return nil;
}

- (NSString *)consoleString
{
  NSAssert(nil, @"consoleString is not yet supported");
  return nil;
}

@end
