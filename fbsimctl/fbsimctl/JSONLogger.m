/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "JSONLogger.h"

#import <asl.h>

#import "fbsimctl-Swift.h"

@interface JSONLogger ()

@property (nonatomic, strong, readonly) JSONEventReporter *reporter;
@property (nonatomic, assign, readonly) int32_t currentLevel;
@property (nonatomic, assign, readonly) int32_t maxLevel;

@end

@implementation JSONLogger

#pragma mark Initializers

+ (instancetype)withEventReporter:(JSONEventReporter *)reporter debug:(BOOL)debug
{
  return [[self alloc] initWithEventReporter:reporter currentLevel:ASL_LEVEL_INFO maxLevel:(debug ? ASL_LEVEL_DEBUG : ASL_LEVEL_INFO)];
}

- (instancetype)initWithEventReporter:(JSONEventReporter *)reporter currentLevel:(int32_t)currentLevel maxLevel:(int32_t)maxLevel
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _reporter = reporter;
  _currentLevel = currentLevel;
  _maxLevel = maxLevel;

  return self;
}

#pragma mark FBSimulatorLogger Interface

- (instancetype)log:(NSString *)string
{
  if (self.currentLevel > self.maxLevel) {
    return self;
  }

  LogEvent *event = [[LogEvent alloc] init:string level:self.currentLevel];
  [self.reporter report:event];
  return self;
}

- (instancetype)logFormat:(NSString *)format, ...
{
  if (self.currentLevel > self.maxLevel) {
    return self;
  }

  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self log:string];
}

- (id<FBSimulatorLogger>)info
{
  return [[JSONLogger alloc] initWithEventReporter:self.reporter currentLevel:ASL_LEVEL_INFO maxLevel:self.maxLevel];
}

- (id<FBSimulatorLogger>)debug
{
  return [[JSONLogger alloc] initWithEventReporter:self.reporter currentLevel:ASL_LEVEL_DEBUG maxLevel:self.maxLevel];
}

- (id<FBSimulatorLogger>)error
{
  return [[JSONLogger alloc] initWithEventReporter:self.reporter currentLevel:ASL_LEVEL_ERR maxLevel:self.maxLevel];
}


@end
