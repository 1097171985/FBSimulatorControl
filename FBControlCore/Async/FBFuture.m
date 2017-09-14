/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFuture.h"

#import "FBCollectionOperations.h"

FBFutureStateString const FBFutureStateStringRunning = @"running";
FBFutureStateString const FBFutureStateStringCompletedWithResult = @"completed_with_result";
FBFutureStateString const FBFutureStateStringCompletedWithError = @"completed_with_error";
FBFutureStateString const FBFutureStateStringCompletedWithCancellation = @"completed_with_cancellation";

FBFutureStateString FBFutureStateStringFromState(FBFutureState state)
{
  switch (state) {
    case FBFutureStateRunning:
      return FBFutureStateStringRunning;
    case FBFutureStateCompletedWithResult:
      return FBFutureStateStringCompletedWithResult;
    case FBFutureStateCompletedWithError:
      return FBFutureStateStringCompletedWithError;
    case FBFutureStateCompletedWithCancellation:
      return FBFutureStateStringCompletedWithCancellation;
  }
  return @"";
}

@interface FBFuture_Handler : NSObject

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) void (^handler)(FBFuture *);

@end

@implementation FBFuture_Handler

- (instancetype)initWithQueue:(dispatch_queue_t)queue handler:(void (^)(FBFuture *))handler
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _queue = queue;
  _handler = handler;

  return self;
}

@end

@interface FBFuture ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) NSMutableArray<FBFuture_Handler *> *handlers;

@end

@implementation FBFuture

@synthesize error = _error, result = _result, state = _state;

#pragma mark Initializers

+ (FBFuture *)futureWithResult:(id)result
{
  FBMutableFuture *future = [self new];
  return [future resolveWithResult:result];
}

+ (FBFuture *)futureWithError:(NSError *)error
{
  FBMutableFuture *future = [self new];
  return [future resolveWithError:error];
}

+ (instancetype)onQueue:(dispatch_queue_t)queue resolveValue:( id(^)(NSError **) )resolve;
{
  FBMutableFuture *future = [self new];
  dispatch_async(queue, ^{
    NSError *error = nil;
    id result = resolve(&error);
    if (!result) {
      NSCAssert(error, @"Error must be set on nil return");
      [future resolveWithError:error];
    }
    [future resolveWithResult:result];
  });
  return future;
}

+ (instancetype)onQueue:(dispatch_queue_t)queue resolve:( FBFuture *(^)(void) )resolve
{
  FBMutableFuture *future = [self new];
  dispatch_async(queue, ^{
    FBFuture *resolved = resolve();
    [future resolveFromFuture:resolved];
  });
  return future;
}

+ (FBFuture *)futureWithFutures:(NSArray<FBFuture *> *)futures
{
  NSParameterAssert(futures.count > 0);

  FBMutableFuture *compositeFuture = [FBMutableFuture new];
  NSMutableArray *results = [[FBCollectionOperations arrayWithObject:NSNull.null count:futures.count] mutableCopy];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.future.composite", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger remaining = futures.count;

  void (^futureCompleted)(FBFuture *, NSUInteger) = ^(FBFuture *future, NSUInteger index) {
    if (compositeFuture.hasCompleted) {
      return;
    }
    FBFutureState state = future.state;
    switch (state) {
      case FBFutureStateCompletedWithResult:
        results[index] = future.result;
        remaining--;
        if (remaining == 0) {
          [compositeFuture resolveWithResult:[results copy]];
        }
        return;
      case FBFutureStateCompletedWithError:
        [compositeFuture resolveWithError:future.error];
        return;
      case FBFutureStateCompletedWithCancellation:
        [compositeFuture resolveAsCancelled];
        return;
      default:
        NSCAssert(NO, @"Unexpected state in callback %@", FBFutureStateStringFromState(state));
        return;
    }
  };

  for (NSUInteger index = 0; index < futures.count; index++) {
    FBFuture *future = futures[index];
    if (future.hasCompleted) {
      futureCompleted(future, index);
    } else {
      [future notifyOfCompletionOnQueue:queue handler:^(FBFuture *innerFuture){
        futureCompleted(innerFuture, index);
      }];
    }
  }
  return compositeFuture;
}

+ (FBFuture *)race:(NSArray<FBFuture *> *)futures
{
  NSParameterAssert(futures.count > 0);

  FBMutableFuture *compositeFuture = [FBMutableFuture new];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.future.race", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger remainingCounter = futures.count;

  void (^cancelAllFutures)(void) = ^{
    for (FBFuture *future in futures) {
      [future cancel];
    }
  };

  void (^futureCompleted)(FBFuture *future) = ^(FBFuture *future){
    remainingCounter--;
    if (future.result) {
      [compositeFuture resolveWithResult:future.result];
      cancelAllFutures();
      return;
    }
    if (future.error) {
      [compositeFuture resolveWithError:future.error];
      cancelAllFutures();
      return;
    }
    if (remainingCounter == 0) {
      [compositeFuture cancel];
    }
  };

  for (FBFuture *future in futures) {
    if (future.hasCompleted) {
      futureCompleted(future);
    } else {
      [future notifyOfCompletionOnQueue:queue handler:futureCompleted];
    }
  }
  return compositeFuture;
}

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _state = FBFutureStateRunning;
  _handlers = [NSMutableArray array];
  _queue = dispatch_queue_create("com.facebook.fbcontrolcore.future", DISPATCH_QUEUE_SERIAL);

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Future %@", FBFutureStateStringFromState(self.state)];
}

#pragma mark FBFuture

- (instancetype)cancel
{
  return [self resolveAsCancelled];
}

- (instancetype)notifyOfCompletionOnQueue:(dispatch_queue_t)queue handler:(void (^)(FBFuture *))handler
{
  dispatch_async(self.queue, ^{
    if (self->_state != FBFutureStateRunning) {
      dispatch_async(queue, ^{
        handler(self);
      });
      return;
    }
    FBFuture_Handler *wrapper = [[FBFuture_Handler alloc] initWithQueue:queue handler:handler];
    [self.handlers addObject:wrapper];
  });
  return self;
}

- (instancetype)notifyOfCancellationOnQueue:(dispatch_queue_t)queue handler:(void (^)(FBFuture *))handler
{
  return [self notifyOfCompletionOnQueue:queue handler:^(FBFuture *future) {
    if (future.state != FBFutureStateCompletedWithCancellation) {
      return;
    }
    handler(future);
  }];
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue chain:(FBFuture *(^)(FBFuture *))chain
{
  FBMutableFuture *chained = FBMutableFuture.future;
  [self notifyOfCompletionOnQueue:queue handler:^(FBFuture *future) {
    if (future.state == FBFutureStateCompletedWithCancellation) {
      [chained cancel];
      return;
    }
    FBFuture *next = chain(future);
    [next notifyOfCompletionOnQueue:queue handler:^(FBFuture *final) {
      FBFutureState state = final.state;
      switch (state) {
        case FBFutureStateCompletedWithError:
          [chained resolveWithError:final.error];
          break;
        case FBFutureStateCompletedWithResult:
          [chained resolveWithResult:final.result];
          break;
        case FBFutureStateCompletedWithCancellation:
          [chained cancel];
          break;
        default:
          NSCAssert(NO, @"Invalid State %lu", (unsigned long)state);
      }
    }];
  }];
  return chained;
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue fmap:(FBFuture * (^)(id result))fmap
{
  FBMutableFuture *chained = FBMutableFuture.future;
  [self notifyOfCompletionOnQueue:queue handler:^(FBFuture *future) {
    if (future.error) {
      [chained resolveWithError:future.error];
      return;
    }
    if (future.state == FBFutureStateCompletedWithCancellation) {
      [chained cancel];
      return;
    }
    [fmap(future.result) notifyOfCompletionOnQueue:queue handler:^(FBFuture *next) {
      if (next.error) {
        [chained resolveWithError:next.error];
        return;
      }
      [chained resolveWithResult:next.result];
    }];
  }];
  return chained;
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue map:(id (^)(id result))map
{
  return [self onQueue:queue fmap:^FBFuture *(id result) {
    id next = map(result);
    return [FBFuture futureWithResult:next];
  }];
}

- (BOOL)hasCompleted
{
  FBFutureState state = self.state;
  return state != FBFutureStateRunning;
}

- (NSError *)error
{
  __block NSError *error;
  dispatch_sync(self.queue, ^{
    error = self->_error;
  });
  return error;
}

- (id)result
{
  __block id result;
  dispatch_sync(self.queue, ^{
    result = self->_result;
  });
  return result;
}

- (FBFutureState)state
{
  __block FBFutureState state;
  dispatch_sync(self.queue, ^{
    state = self->_state;
  });
  return state;
}

#pragma mark FBMutableFuture Implementation

static NSString *KeyPathError = @"error";
static NSString *KeyPathResult = @"result";
static NSString *KeyPathState = @"state";
static NSString *KeyPathHasCompleted = @"hasCompleted";

- (instancetype)resolveWithResult:(id)result
{
  dispatch_async(self.queue, ^{
    if (self->_state != FBFutureStateRunning) {
      return;
    }

    [self willChangeValueForKey:KeyPathResult];
    [self willChangeValueForKey:KeyPathState];
    [self willChangeValueForKey:KeyPathHasCompleted];
    self->_result = result;
    self->_state = FBFutureStateCompletedWithResult;
    [self didChangeValueForKey:KeyPathResult];
    [self didChangeValueForKey:KeyPathState];
    [self didChangeValueForKey:KeyPathHasCompleted];
    [self fireAllHandlers];
  });
  return self;
}

- (instancetype)resolveWithError:(NSError *)error
{
  dispatch_async(self.queue, ^{
    if (self->_state != FBFutureStateRunning) {
      return;
    }

    [self willChangeValueForKey:KeyPathError];
    [self willChangeValueForKey:KeyPathState];
    [self willChangeValueForKey:KeyPathHasCompleted];
    self->_error = error;
    self->_state = FBFutureStateCompletedWithError;
    [self didChangeValueForKey:KeyPathError];
    [self didChangeValueForKey:KeyPathState];
    [self didChangeValueForKey:KeyPathHasCompleted];
    [self fireAllHandlers];
  });
  return self;
}

- (instancetype)resolveAsCancelled
{
  dispatch_async(self.queue, ^{
    if (self->_state != FBFutureStateRunning) {
      return;
    }

    [self willChangeValueForKey:KeyPathState];
    [self willChangeValueForKey:KeyPathHasCompleted];
    self->_state = FBFutureStateCompletedWithCancellation;
    [self didChangeValueForKey:KeyPathState];
    [self didChangeValueForKey:KeyPathHasCompleted];
    [self fireAllHandlers];
  });
  return self;
}

- (void)fireAllHandlers
{
  for (FBFuture_Handler *handler in self.handlers) {
    dispatch_async(handler.queue, ^{
      handler.handler(self);
    });
  }
  [self.handlers removeAllObjects];
}

- (instancetype)resolveFromFuture:(FBFuture *)future
{
  void (^resolve)(FBFuture *future) = ^(FBFuture *resolvedFuture){
    FBFutureState state = resolvedFuture.state;
    switch (state) {
      case FBFutureStateCompletedWithError:
        [self resolveWithError:resolvedFuture.error];
        return;
      case FBFutureStateCompletedWithResult:
        [self resolveWithResult:resolvedFuture.result];
        return;
      case FBFutureStateCompletedWithCancellation:
        [self cancel];
        return;
      default:
        NSCAssert(NO, @"Invalid State %lu", (unsigned long)state);
    }
  };
  if (future.hasCompleted) {
    resolve(future);
  } else {
    [future notifyOfCompletionOnQueue:self.queue handler:resolve];
  }
  return self;
}

@end

@implementation FBMutableFuture

- (instancetype)resolveWithError:(NSError *)error
{
  return [super resolveWithError:error];
}

- (instancetype)resolveWithResult:(id)result
{
  return [super resolveWithResult:result];
}

+ (FBMutableFuture *)future
{
  return [FBMutableFuture new];
}

@end
