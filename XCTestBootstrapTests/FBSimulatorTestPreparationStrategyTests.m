// Copyright 2004-present Facebook. All Rights Reserved.

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>

#import "FBDeviceOperator.h"
#import "FBFileManager.h"
#import "FBSimulatorTestPreparationStrategy.h"
#import "FBTestRunnerConfiguration.h"

@interface FBSimulatorTestPreparationStrategyTests : XCTestCase
@end

@implementation FBSimulatorTestPreparationStrategyTests

+ (BOOL)isGoodConfigurationPath:(NSString *)path
{
  return [path rangeOfString:@"\\/heaven\\/testBundle\\/testBundle-(.*)\\.xctestconfiguration" options:NSRegularExpressionSearch].location != NSNotFound;
}

- (void)testStrategyWithMissingWorkingDirectory
{
  FBSimulatorTestPreparationStrategy *strategy =
  [FBSimulatorTestPreparationStrategy strategyWithApplicationPath:@""
                                                   testBundlePath:@""
                                                 workingDirectory:nil
                                                      fileManager:nil];
  XCTAssertThrows([strategy prepareTestWithDeviceOperator:[OCMockObject niceMockForProtocol:@protocol(FBDeviceOperator)] error:nil]);
}

- (void)testStrategyWithMissingTestBundlePath
{
  FBSimulatorTestPreparationStrategy *strategy =
  [FBSimulatorTestPreparationStrategy strategyWithApplicationPath:@""
                                                   testBundlePath:nil
                                                 workingDirectory:@""
                                                      fileManager:nil];
  XCTAssertThrows([strategy prepareTestWithDeviceOperator:[OCMockObject niceMockForProtocol:@protocol(FBDeviceOperator)] error:nil]);
}

- (void)testStrategyWithMissingApplicationPath
{
  FBSimulatorTestPreparationStrategy *strategy =
  [FBSimulatorTestPreparationStrategy strategyWithApplicationPath:nil
                                                   testBundlePath:@""
                                                 workingDirectory:@""
                                                      fileManager:nil];
  XCTAssertThrows([strategy prepareTestWithDeviceOperator:[OCMockObject niceMockForProtocol:@protocol(FBDeviceOperator)] error:nil]);
}

- (void)testSimulatorPreparation
{
  id xctConfigArg = [OCMArg checkWithBlock:^BOOL(NSString *path){return [self.class isGoodConfigurationPath:path];}];
  NSDictionary *plist =
  @{
    @"CFBundleIdentifier" : @"bundleID",
    @"CFBundleExecutable" : @"exec",
  };

  OCMockObject<FBFileManager> *fileManagerMock = [OCMockObject mockForProtocol:@protocol(FBFileManager)];
  [[[fileManagerMock stub] andReturn:plist] dictionaryWithPath:[OCMArg any]];
  [[[fileManagerMock expect] andReturnValue:@YES] copyItemAtPath:@"/testBundle" toPath:@"/heaven/testBundle" error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] writeData:[OCMArg any] toFile:xctConfigArg options:0 error:[OCMArg anyObjectRef]];

  OCMockObject<FBDeviceOperator> *deviceOperatorMock = [OCMockObject mockForProtocol:@protocol(FBDeviceOperator)];
  [[[deviceOperatorMock expect] andReturnValue:@YES] installApplicationWithPath:@"/app" error:[OCMArg anyObjectRef]];

  FBSimulatorTestPreparationStrategy *strategy =
  [FBSimulatorTestPreparationStrategy strategyWithApplicationPath:@"/app"
                                                   testBundlePath:@"/testBundle"
                                                 workingDirectory:@"/heaven"
                                                      fileManager:fileManagerMock];
  FBTestRunnerConfiguration *configuration = [strategy prepareTestWithDeviceOperator:deviceOperatorMock error:nil];

  NSDictionary *env = configuration.launchEnvironment;
  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.testRunner);
  XCTAssertNotNil(configuration.launchArguments);
  XCTAssertNotNil(env);
  XCTAssertEqualObjects(env[@"AppTargetLocation"], @"/app/exec");
  XCTAssertEqualObjects(env[@"TestBundleLocation"], @"/heaven/testBundle");
  XCTAssertEqualObjects(env[@"XCInjectBundle"], @"/heaven/testBundle");
  XCTAssertEqualObjects(env[@"XCInjectBundleInto"], @"/app/exec");
  XCTAssertNotNil(env[@"DYLD_INSERT_LIBRARIES"]);
  XCTAssertTrue([self.class isGoodConfigurationPath:configuration.launchEnvironment[@"XCTestConfigurationFilePath"]],
                @"XCTestConfigurationFilePath should be like /heaven/testBundle/testBundle-[UDID].xctestconfiguration but is %@",
                env[@"XCTestConfigurationFilePath"]
                );
  [fileManagerMock verify];
  [deviceOperatorMock verify];
}

@end
