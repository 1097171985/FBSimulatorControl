/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBDeviceControl/FBDeviceControl.h>

@interface FBAMDeviceTests : XCTestCase

@property (nonatomic, strong, readwrite, class) NSMutableArray<NSString *> *events;
@property (nonatomic, strong, readwrite) FBAMDevice *device;

@end

static void Retain(AMDeviceRef ref)
{

}

static void Release(AMDeviceRef ref)
{

}

static int Connect(AMDeviceRef ref)
{
  [FBAMDeviceTests.events addObject:@"connect"];
  return 0;
}

static int Disconnect(AMDeviceRef ref)
{
  [FBAMDeviceTests.events addObject:@"disconnect"];
  return 0;
}

static int StartSession(AMDeviceRef ref)
{
  [FBAMDeviceTests.events addObject:@"start_session"];
  return 0;
}

static int StopSession(AMDeviceRef ref)
{
  [FBAMDeviceTests.events addObject:@"stop_session"];
  return 0;
}

static int SecureStartService(AMDeviceRef device, CFStringRef service_name, CFDictionaryRef userinfo, CFTypeRef *serviceOut)
{
  [FBAMDeviceTests.events addObject:@"secure_start_service"];
  *serviceOut = CFSTR("A Service");
  return 0;
}

static int ServiceConnectionInvalidate(CFTypeRef connection)
{
  [FBAMDeviceTests.events addObject:@"service_connection_invalidate"];
  return 0;
}

static CFStringRef CopyValue(AMDeviceRef device, CFStringRef domain, CFStringRef name)
{
  return name;
}

static int CreateHouseArrestService(AMDeviceRef device, CFStringRef bundleID, void *unused, AFCConnectionRef *connectionOut)
{
  [FBAMDeviceTests.events addObject:@"create_house_arrest_service"];
  *connectionOut = (AFCConnectionRef) CFSTR("A HOUSE ARREST");
  return 0;
}

static int ConnectionClose(AFCConnectionRef connection)
{
  [FBAMDeviceTests.events addObject:@"connection_close"];
  return 0;
}

@implementation FBAMDeviceTests

static NSMutableArray<NSString *> *sEvents;

+ (NSMutableArray<NSString *> *)events
{
  if (!sEvents){
    sEvents = [NSMutableArray array];
  }
  return sEvents;
}

+ (void)setEvents:(NSMutableArray<NSString *> *)events
{
  sEvents = events;
}

- (AMDeviceRef)deviceRef
{
  return (AMDeviceRef) CFSTR("A DEVICE");
}

- (AMDCalls)stubbedCalls
{
  AMDCalls calls = {
    .Retain = Retain,
    .Release = Release,
    .Connect = Connect,
    .Disconnect = Disconnect,
    .StartSession = StartSession,
    .StopSession = StopSession,
    .CopyValue = CopyValue,
    .SecureStartService = SecureStartService,
    .CreateHouseArrestService = CreateHouseArrestService,
    .ServiceConnectionInvalidate = ServiceConnectionInvalidate,
  };
  return calls;
}

- (void)setUp
{
  [FBAMDeviceTests.events removeAllObjects];

  FBAMDevice *device = [[FBAMDevice alloc] initWithUDID:@"foo" calls:self.stubbedCalls workQueue:dispatch_get_main_queue() logger:FBControlCoreGlobalConfiguration.defaultLogger];
  NSArray<NSString *> *events = [FBAMDeviceTests.events copy];
  XCTAssertEqualObjects(events, @[]);

  device.amDevice = self.deviceRef;
  events = [FBAMDeviceTests.events copy];
  XCTAssertEqualObjects(events, (@[
    @"connect",
    @"start_session",
    @"stop_session",
    @"disconnect",
  ]));

  [FBAMDeviceTests.events removeAllObjects];
  self.device = device;
}

- (void)tearDown
{
  self.device = nil;
}

- (void)testConnectToDeviceWithSuccess
{
  FBFuture<NSNull *> *future = [[self.device connectToDeviceWithPurpose:@"test"] onQueue:dispatch_get_main_queue() fmap:^(FBAMDevice *result) {
    return [FBFuture futureWithResult:NSNull.null];
  }];

  NSError *error = nil;
  id value = [future await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(value);

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"start_session",
    @"stop_session",
    @"disconnect",
  ];

  XCTAssertEqualObjects(expected, actual);
}

- (void)testConnectToDeviceWithFailure
{
  FBFuture<NSNull *> *future = [[self.device connectToDeviceWithPurpose:@"test"] onQueue:dispatch_get_main_queue() fmap:^(FBAMDevice *result) {
    return [[FBDeviceControlError describeFormat:@"A bad thing"] failFuture];
  }];

  NSError *error = nil;
  id value = [future await:&error];
  XCTAssertNotNil(error);
  XCTAssertNil(value);

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"start_session",
    @"stop_session",
    @"disconnect",
  ];

  XCTAssertEqualObjects(expected, actual);
}

- (void)testStartAFCService
{
  FBFuture<FBAMDServiceConnection *> *future = [[self.device startAFCService] onQueue:dispatch_get_main_queue() fmap:^(FBAMDServiceConnection *result) {
    return [FBFuture futureWithResult:result];
  }];

  NSError *error = nil;
  id value = [future await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(value);

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"start_session",
    @"secure_start_service",
    @"service_connection_invalidate",
    @"stop_session",
    @"disconnect",
  ];

  XCTAssertEqualObjects(expected, actual);
}

- (void)testHouseArrest
{
  AFCCalls afcCalls = {
    .ConnectionClose = ConnectionClose,
  };

  FBFuture<FBAFCConnection *> *future = [[self.device houseArrestAFCConnectionForBundleID:@"com.foo.bar" afcCalls:afcCalls] onQueue:dispatch_get_main_queue() fmap:^(FBAFCConnection *result) {
    return [FBFuture futureWithResult:result];
  }];

  NSError *error = nil;
  id value = [future await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(value);

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"start_session",
    @"create_house_arrest_service",
    @"connection_close",
    @"stop_session",
    @"disconnect",
  ];

  XCTAssertEqualObjects(expected, actual);
}

- (void)testConcurrentUtilizationHasSharedConnection
{
  dispatch_queue_t schedule = dispatch_queue_create("com.facebook.fbdevicecontrol.amdevicetests.schedule", DISPATCH_QUEUE_CONCURRENT);
  dispatch_queue_t map = dispatch_queue_create("com.facebook.fbdevicecontrol.amdevicetests.map", DISPATCH_QUEUE_SERIAL);
  FBMutableFuture<NSNumber *> *future0 = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *future1 = FBMutableFuture.future;
  FBMutableFuture<NSNumber *> *future2 = FBMutableFuture.future;

  FBAMDevice *device = self.device;
  dispatch_async(schedule, ^{
    FBFuture<NSNumber *> *future = [[device connectToDeviceWithPurpose:@"test"] onQueue:map fmap:^(FBAMDevice *result) {
      return [FBFuture futureWithResult:@0];
    }];
    [future0 resolveFromFuture:future];
  });
  dispatch_async(schedule, ^{
    FBFuture<NSNumber *> *future = [[device connectToDeviceWithPurpose:@"test"] onQueue:map fmap:^(FBAMDevice *result) {
      return [FBFuture futureWithResult:@1];
    }];
    [future1 resolveFromFuture:future];
  });
  dispatch_async(schedule, ^{
    FBFuture<NSNumber *> *future = [[device connectToDeviceWithPurpose:@"test"] onQueue:map fmap:^(FBAMDevice *result) {
      return [FBFuture futureWithResult:@2];
    }];
    [future2 resolveFromFuture:future];
  });


  NSError *error = nil;
  NSArray<NSNumber *> *value = [[FBFuture futureWithFutures:@[future0, future1, future2]] await:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(value, (@[@0, @1, @2]));

  NSArray<NSString *> *actual = [FBAMDeviceTests.events copy];
  NSArray<NSString *> *expected = @[
    @"connect",
    @"start_session",
    @"stop_session",
    @"disconnect",
  ];
  XCTAssertEqualObjects(expected, actual);
}

@end
