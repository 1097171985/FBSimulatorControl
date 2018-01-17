/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBFileConsumer;
@protocol FBXCTestProcessExecutor;

@class FBLaunchedProcess;
@class FBSimulator;
@class FBXCTestProcess;

/**
 A Platform-Agnostic wrapper responsible for managing an xctest process.
 Driven by an executor, which implements the platform-specific responsibilities of launching an xctest process.
 */
@interface FBXCTestProcess : NSObject

/**
 The Designated Initializer.

 @param launchPath the Launch Path of the executable
 @param arguments the Arguments to the executable.
 @param environment the Environment Variables to set.
 @param stdOutConsumer the Consumer of the launched xctest process stdout.
 @param stdErrConsumer the Consumer of the launched xctest process stderr.
 @param executor the executor for running the test process.
 @return a new xctest process.
 */
+ (instancetype)processWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutConsumer:(id<FBFileConsumer>)stdOutConsumer stdErrConsumer:(id<FBFileConsumer>)stdErrConsumer executor:(id<FBXCTestProcessExecutor>)executor;

/**
 Starts the Process.

 @param timeout the timeout in seconds for the process to terminate.
 @return a Future that will resolve when the process info when launched.
 */
- (FBFuture<id<FBLaunchedProcess>> *)startWithTimeout:(NSTimeInterval)timeout;

#pragma mark Properties

/**
 The Launch Path of the xctest process.
 */
@property (nonatomic, copy, readonly) NSString *launchPath;

/**
 The Arguments of the xctest process.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;

/**
 The environment of the xctest process.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *environment;

/**
 Whether the process will be launched in a SIGSTOP state.
 */
@property (nonatomic, assign, readonly) BOOL waitForDebugger;

/**
 The consumer of stdout.
 */
@property (nonatomic, strong, readonly) id<FBFileConsumer> stdOutConsumer;

/**
 The consumer of stderr.
 */
@property (nonatomic, strong, readonly) id<FBFileConsumer> stdErrConsumer;

@end

NS_ASSUME_NONNULL_END
