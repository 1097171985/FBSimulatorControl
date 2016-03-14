// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBSimulatorTestPreparationStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBDeviceOperator.h"
#import "FBFileManager.h"
#import "FBProductBundle.h"
#import "FBTestBundle.h"
#import "FBTestConfiguration.h"
#import "FBTestRunnerConfiguration.h"
#import "NSFileManager+FBFileManager.h"

@interface FBSimulatorTestPreparationStrategy ()
@property (nonatomic, copy) NSString *workingDirectory;
@property (nonatomic, copy) NSString *applicationPath;
@property (nonatomic, copy) NSString *testBundlePath;
@property (nonatomic, strong) id<FBFileManager> fileManager;
@end

@implementation FBSimulatorTestPreparationStrategy

+ (instancetype)strategyWithApplicationPath:(NSString *)applicationPath
                             testBundlePath:(NSString *)testBundlePath
                           workingDirectory:(NSString *)workingDirectory
{
  return
  [self strategyWithApplicationPath:applicationPath
                     testBundlePath:testBundlePath
                   workingDirectory:workingDirectory
                        fileManager:[NSFileManager defaultManager]
   ];
}

+ (instancetype)strategyWithApplicationPath:(NSString *)applicationPath
                             testBundlePath:(NSString *)testBundlePath
                           workingDirectory:(NSString *)workingDirectory
                                fileManager:(id<FBFileManager>)fileManager
{
  FBSimulatorTestPreparationStrategy *strategy = [self.class new];
  strategy.applicationPath = applicationPath;
  strategy.testBundlePath = testBundlePath;
  strategy.workingDirectory = workingDirectory;
  strategy.fileManager = fileManager;
  return strategy;
}

#pragma mark - FBTestPreparationStrategy protocol

- (FBTestRunnerConfiguration *)prepareTestWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator error:(NSError **)error
{
  NSAssert(deviceOperator, @"deviceOperator is needed to load bundles");
  NSAssert(self.workingDirectory, @"Working directory is needed to prepare bundles");
  NSAssert(self.applicationPath, @"Path to application is needed to load bundles");
  NSAssert(self.testBundlePath, @"Path to test bundle is needed to load bundles");

  FBProductBundle *application =
  [[[FBProductBundleBuilder builderWithFileManager:self.fileManager]
    withBundlePath:self.applicationPath]
   build];

  // Install tested application
  if (![deviceOperator installApplicationWithPath:self.applicationPath error:error]) {
    return nil;
  }

  // Prepare XCTest bundle
  NSUUID *sessionIdentifier = [NSUUID UUID];
  FBTestBundle *testBundle =
  [[[[[FBTestBundleBuilder builderWithFileManager:self.fileManager]
      withBundlePath:self.testBundlePath]
     withWorkingDirectory:self.workingDirectory]
    withSessionIdentifier:sessionIdentifier]
   build];

  NSString *IDEBundleInjectionFrameworkPath =
  [FBControlCoreGlobalConfiguration.developerDirectory stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform/Developer/Library/PrivateFrameworks/IDEBundleInjection.framework"];
  FBProductBundle *IDEBundleInjectionFramework =
  [[[FBProductBundleBuilder builder]
    withBundlePath:IDEBundleInjectionFrameworkPath]
   build];

  return
  [[[[[[[FBTestRunnerConfigurationBuilder builder]
        withSessionIdentifer:sessionIdentifier]
       withTestRunnerApplication:application]
      withIDEBundleInjectionFramework:IDEBundleInjectionFramework]
     withWebDriverAgentTestBundle:testBundle]
    withTestConfigurationPath:testBundle.configuration.path]
   build];
}

@end
