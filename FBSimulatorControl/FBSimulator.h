/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorApplication;
@class FBSimulatorPool;
@class SimDevice;

/**
 The Default timeout for waits
 */
extern NSTimeInterval const FBSimulatorDefaultTimeout;

/**
 Uses the known values of SimDevice State, to construct an enumeration
 */
typedef NS_ENUM(NSInteger, FBSimulatorState) {
  FBSimulatorStateBooted,
  FBSimulatorStateCreating,
  FBSimulatorStateShutdown,
  FBSimulatorStateUnknown = -1,
};

/**
 Wraps SimDevice, with additional information about the device.
 */
@interface FBSimulator : NSObject

/**
 Whether the Simulator is Allocated.
 */
@property (nonatomic, assign, readonly, getter=isAllocated) BOOL allocated;

/**
 The Underlying SimDevice.
 */
@property (nonatomic, strong, readonly) SimDevice *device;

/**
 The Pool to which the Simulator Belongs.
 */
@property (nonatomic, weak, readonly) FBSimulatorPool *pool;

/**
 The Bucket ID of the allocated device. Bucket IDs are used to segregate a range of devices, so that multiple
 processes can use Simulators, without colliding
 */
@property (nonatomic, assign, readonly) NSInteger bucketID;

/**
 The Offset represents the position in the pool of this device. Multiple devices of the same type can be allocated in the same pool.
 */
@property (nonatomic, assign, readonly) NSInteger offset;

/**
 The Name of the allocated device.
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 The UDID of the allocated device.
 */
@property (nonatomic, copy, readonly) NSString *udid;

/**
 The State of the allocated device.
 */
@property (nonatomic, assign, readonly) FBSimulatorState state;

/**
 The Application that the Simulator should be launched with.
 */
@property (nonatomic, copy, readonly) FBSimulatorApplication *simulatorApplication;

/**
 The Process Identifier of the Simulator. -1 if it is not running
 */
@property (nonatomic, assign, readonly) NSInteger processIdentifier;

/**
 The Directory that Contains the Simulator's Data
 */
@property (nonatomic, copy, readonly) NSString *dataDirectory;

/**
 Calls `freeSimulator:error:` on this device's pool, with the reciever as the first argument

 @param error an error out for any error that occured.
 @returns YES if the freeing of the device was successful, NO otherwise.
 */
- (BOOL)freeFromPoolWithError:(NSError **)error;

/**
 Synchronously waits on the provided state.

 @param state the state to wait on
 @returns YES if the Simulator transitioned to the given state with the default timeout, NO otherwise
 */
- (BOOL)waitOnState:(FBSimulatorState)state;

/**
 Synchronously waits on the provided state.

 @param state the state to wait on
 @param the timeout
 @returns YES if the Simulator transitioned to the given state with the timeout, NO otherwise
 */
- (BOOL)waitOnState:(FBSimulatorState)state timeout:(NSTimeInterval)timeout;

@end
