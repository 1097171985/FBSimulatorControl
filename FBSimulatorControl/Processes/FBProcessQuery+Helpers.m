/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessQuery+Helpers.h"

#import <AppKit/AppKit.h>

#import "FBProcessInfo.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

@implementation FBProcessQuery (Helpers)

- (FBProcessInfo *)processInfoFor:(pid_t)processIdentifier timeout:(NSTimeInterval)timeout
{
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilExists:^ FBProcessInfo * {
    return [self processInfoFor:processIdentifier];
  }];
}

- (BOOL)waitForProcessToDie:(FBProcessInfo *)process timeout:(NSTimeInterval)timeout
{
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^ BOOL {
    FBProcessInfo *polledProcess = [self processInfoFor:process.processIdentifier];
    if (!polledProcess) {
      return YES;
    }
    if (![process isEqual:polledProcess]) {
      return YES;
    }
    return NO;
  }];
}

- (NSArray *)runningApplicationsForProcesses:(NSArray *)processes
{
  return [self.processIdentifiersToApplications objectsForKeys:[processes valueForKey:@"processIdentifier"] notFoundMarker:NSNull.null];
}

- (NSRunningApplication *)runningApplicationForProcess:(FBProcessInfo *)process
{
  NSRunningApplication *application = [[self
    runningApplicationsForProcesses:@[process]]
    firstObject];

  if (![application isKindOfClass:NSRunningApplication.class]) {
    return nil;
  }

  return application;
}

#pragma mark Private

- (NSDictionary *)processIdentifiersToApplications
{
  NSArray *applications = NSWorkspace.sharedWorkspace.runningApplications;
  NSArray *processIdentifiers = [applications valueForKey:@"processIdentifier"];
  return [NSDictionary dictionaryWithObjects:applications forKeys:processIdentifiers];
}

@end
