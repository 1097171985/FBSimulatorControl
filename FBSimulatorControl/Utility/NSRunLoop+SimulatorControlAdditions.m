/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "NSRunLoop+SimulatorControlAdditions.h"

@implementation NSRunLoop (SimulatorControlAdditions)

- (BOOL)spinRunLoopWithTimeout:(NSTimeInterval)timeout untilTrue:( BOOL (^)(void) )untilTrue
{
  NSDate *date = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while (!untilTrue()) {
    @autoreleasepool {
      if ([date timeIntervalSinceNow] < 0) {
        return NO;
      }
      // Wait for 1s
      [self runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    }
  }
  return YES;
}

@end
