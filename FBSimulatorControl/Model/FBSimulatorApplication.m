/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorApplication.h"

#import "FBConcurrentCollectionOperations.h"
#import "FBSimulatorControlStaticConfiguration.h"
#import "FBSimulatorError.h"
#import "FBTaskExecutor.h"

@implementation FBSimulatorBinary

- (instancetype)initWithName:(NSString *)name path:(NSString *)path architectures:(NSSet *)architectures
{
  NSParameterAssert(name);
  NSParameterAssert(path);
  NSParameterAssert(architectures);

  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _path = path;
  _architectures = architectures;

  return self;
}

+ (instancetype)withName:(NSString *)name path:(NSString *)path architectures:(NSSet *)architectures
{
  if (!name || !path || !architectures) {
    return nil;
  }
  return [[self alloc] initWithName:name path:path architectures:architectures];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBSimulatorBinary alloc]
    initWithName:self.name
    path:self.path
    architectures:self.architectures];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _name = [coder decodeObjectForKey:NSStringFromSelector(@selector(name))];
  _path = [coder decodeObjectForKey:NSStringFromSelector(@selector(path))];
  _architectures = [coder decodeObjectForKey:NSStringFromSelector(@selector(architectures))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.name forKey:NSStringFromSelector(@selector(name))];
  [coder encodeObject:self.path forKey:NSStringFromSelector(@selector(path))];
  [coder encodeObject:self.architectures forKey:NSStringFromSelector(@selector(architectures))];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBSimulatorBinary *)object
{
  if (![object isMemberOfClass:self.class]) {
    return NO;
  }
  return [object.name isEqual:self.name] &&
         [object.path isEqual:self.path] &&
         [object.architectures isEqual:self.architectures];
}

- (NSUInteger)hash
{
  return self.name.hash | self.path.hash | self.architectures.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Name: %@ | Path: %@ | Architectures: %@", self.name, self.path, self.architectures];
}

@end

@implementation FBSimulatorApplication

- (instancetype)initWithName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID binary:(FBSimulatorBinary *)binary
{
  NSParameterAssert(name);
  NSParameterAssert(path);
  NSParameterAssert(bundleID);
  NSParameterAssert(binary);

  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _path = path;
  _bundleID = bundleID;
  _binary = binary;

  return self;
}

+ (instancetype)withName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID binary:(FBSimulatorBinary *)binary
{
  if (!name || !path || !bundleID || !binary) {
    return nil;
  }
  return [[self alloc] initWithName:name path:path bundleID:bundleID binary:binary];
}

#pragma mark NSCopying

- (FBSimulatorApplication *)copyWithZone:(NSZone *)zone
{
  return [[FBSimulatorApplication alloc]
    initWithName:self.name
    path:self.path
    bundleID:self.bundleID
    binary:self.binary];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  NSString *name = [coder decodeObjectForKey:NSStringFromSelector(@selector(name))];
  NSString *path = [coder decodeObjectForKey:NSStringFromSelector(@selector(path))];
  NSString *bundleID = [coder decodeObjectForKey:NSStringFromSelector(@selector(bundleID))];
  FBSimulatorBinary *binary = [coder decodeObjectForKey:NSStringFromSelector(@selector(binary))];

  return [[FBSimulatorApplication alloc]
    initWithName:name
    path:path
    bundleID:bundleID
    binary:binary];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.name forKey:NSStringFromSelector(@selector(name))];
  [coder encodeObject:self.path forKey:NSStringFromSelector(@selector(path))];
  [coder encodeObject:self.bundleID forKey:NSStringFromSelector(@selector(bundleID))];
  [coder encodeObject:self.binary forKey:NSStringFromSelector(@selector(binary))];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBSimulatorApplication *)object
{
  if (![object isMemberOfClass:self.class]) {
    return NO;
  }
  return [object.name isEqual:self.name] &&
         [object.path isEqual:self.path] &&
         [object.bundleID isEqual:self.bundleID] &&
         [object.binary isEqual:self.binary];
}

- (NSUInteger)hash
{
  return self.name.hash | self.path.hash | self.bundleID.hash | self.binary.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Name: %@ | ID: %@ | Path: %@ | Binary (%@)", self.name, self.bundleID, self.path, self.binary];
}

@end

@implementation FBSimulatorApplication (Helpers)

+ (instancetype)applicationWithPath:(NSString *)path error:(NSError **)error;
{
  if (!path) {
    return [[FBSimulatorError describe:@"Path is nil for Application"] fail:error];
  }

  return [[FBSimulatorApplication alloc]
    initWithName:[self appNameForPath:path]
    path:path
    bundleID:[self bundleIDForAppAtPath:path]
    binary:[self binaryForApplicationPath:path]];
}

+ (NSArray *)simulatorApplicationsFromPaths:(NSArray *)paths
{
  return [FBConcurrentCollectionOperations
    generate:paths.count
    withBlock:^ FBSimulatorApplication * (NSUInteger index) {
      return [FBSimulatorApplication applicationWithPath:paths[index] error:nil];
    }];
}

+ (instancetype)simulatorApplicationWithError:(NSError **)error
{
  NSString *simulatorBinaryName = [FBSimulatorControlStaticConfiguration.sdkVersionNumber isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"9.0"]]
    ? @"Simulator"
    : @"iOS Simulator";

  NSString *appPath = [[FBSimulatorControlStaticConfiguration.developerDirectory
    stringByAppendingPathComponent:@"Applications"]
    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.app", simulatorBinaryName]];

  NSError *innerError = nil;
  FBSimulatorApplication *application = [self applicationWithPath:appPath error:&innerError];
  if (!application) {
    NSString *message = [NSString stringWithFormat:@"Could not locate Simulator Application at %@", appPath];
    return [FBSimulatorError failWithError:innerError description:message errorOut:error];
  }
  return application;
}

+ (NSArray *)simulatorSystemApplications;
{
  static dispatch_once_t onceToken;
  static NSArray *applications;
  dispatch_once(&onceToken, ^{
    NSString *systemAppsDirectory = [FBSimulatorControlStaticConfiguration.developerDirectory
      stringByAppendingPathComponent:@"/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/Applications"];

    NSMutableArray *fullPaths = [NSMutableArray array];
    for (NSString *contentPath in [NSFileManager.defaultManager contentsOfDirectoryAtPath:systemAppsDirectory error:nil]) {
      [fullPaths addObject:[systemAppsDirectory stringByAppendingPathComponent:contentPath]];
    }
    applications = [self simulatorApplicationsFromPaths:fullPaths];
  });
  return applications;
}

+ (instancetype)systemApplicationNamed:(NSString *)appName
{
  for (FBSimulatorApplication *application in self.simulatorSystemApplications) {
    if ([application.name isEqual:appName]) {
      return application;
    }
  }
  return nil;
}

#pragma mark Private

+ (FBSimulatorBinary *)binaryForApplicationPath:(NSString *)applicationPath
{
  NSString *binaryPath = [self binaryPathForAppAtPath:applicationPath];
  return [FBSimulatorBinary binaryWithPath:binaryPath error:nil];
}

+ (NSString *)appNameForPath:(NSString *)appPath
{
  return [[appPath lastPathComponent] stringByDeletingPathExtension];
}

+ (NSString *)binaryNameForAppAtPath:(NSString *)appPath
{
  NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:[self infoPlistPathForAppAtPath:appPath]];
  return infoPlist[@"CFBundleExecutable"];
}

+ (NSString *)binaryPathForAppAtPath:(NSString *)appPath
{
  NSString *binaryName = [self binaryNameForAppAtPath:appPath];
  NSString *binaryPathIOS = [appPath stringByAppendingPathComponent:binaryName];
  if ([NSFileManager.defaultManager fileExistsAtPath:binaryPathIOS]) {
    return binaryPathIOS;
  }

  NSString *binaryPathMacOS = [[appPath
    stringByAppendingPathComponent:@"Contents/MacOS"]
    stringByAppendingPathComponent:binaryName];
  if ([NSFileManager.defaultManager fileExistsAtPath:binaryPathMacOS]) {
    return binaryPathMacOS;
  }

  return nil;
}

+ (NSString *)bundleIDForAppAtPath:(NSString *)appPath
{
  NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:[self infoPlistPathForAppAtPath:appPath]];
  return infoPlist[@"CFBundleIdentifier"];
}

+ (NSString *)infoPlistPathForAppAtPath:(NSString *)appPath
{
  NSString *plistPath = [appPath stringByAppendingPathComponent:@"info.plist"];
  if ([NSFileManager.defaultManager fileExistsAtPath:plistPath]) {
    return plistPath;
  }

  plistPath = [[appPath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"Info.plist"];
  if ([NSFileManager.defaultManager fileExistsAtPath:plistPath]) {
    return plistPath;
  }
  return nil;
}

@end

@implementation FBSimulatorBinary (Helpers)

+ (instancetype)binaryWithPath:(NSString *)binaryPath error:(NSError **)error;
{
  if (!binaryPath) {
    return nil;
  }
  NSSet *archs = [self binaryArchitecturesForBinaryPath:binaryPath];
  if (!archs) {
    return nil;
  }

  return [[FBSimulatorBinary alloc]
    initWithName:[binaryPath lastPathComponent]
    path:binaryPath
    architectures:archs];
}

+ (NSSet *)binaryArchitecturesForBinaryPath:(NSString *)binaryPath
{
  NSString *fileOutput = [[[FBTaskExecutor.sharedInstance
    taskWithLaunchPath:@"/usr/bin/file" arguments:@[binaryPath]]
    startSynchronouslyWithTimeout:30]
    stdOut];

  NSArray *matches = [self.fileArchRegex
    matchesInString:fileOutput
    options:(NSMatchingOptions)0
    range:NSMakeRange(0, fileOutput.length)];

  NSMutableArray *architectures = [NSMutableArray array];
  for (NSTextCheckingResult *result in matches) {
    [architectures addObject:[fileOutput substringWithRange:[result rangeAtIndex:1]]];
  }

  return [NSSet setWithArray:architectures];
}

+ (NSRegularExpression *)fileArchRegex
{
  static dispatch_once_t onceToken;
  static NSRegularExpression *regex;
  dispatch_once(&onceToken, ^{
    regex = [NSRegularExpression
      regularExpressionWithPattern:@"executable (\\w+)"
      options:NSRegularExpressionAnchorsMatchLines
      error:nil];
  });
  return regex;
}

@end
