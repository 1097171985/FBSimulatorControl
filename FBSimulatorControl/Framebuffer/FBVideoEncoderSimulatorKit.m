/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBVideoEncoderSimulatorKit.h"

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>
#import <xpc/xpc.h>
#import <IOSurface/IOSurface.h>

#import <SimulatorKit/SimDisplayVideoWriter.h>
#import <SimulatorKit/SimDisplayVideoWriter+Removed.h>

#import "FBFramebufferSurface.h"
#import "FBSimulatorError.h"

@interface FBVideoEncoderSimulatorKit () <FBFramebufferSurfaceConsumer>

@property (nonatomic, strong, readonly) FBFramebufferSurface *surface;
@property (nonatomic, strong, readonly) SimDisplayVideoWriter *writer;
@property (nonatomic, strong, readonly) SimVideoFile *videoFile;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) FBFuture<NSNull *> *finishedWriting;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *startedWriting;

@end

@implementation FBVideoEncoderSimulatorKit

#pragma mark Initializers

+ (instancetype)encoderWithRenderable:(FBFramebufferSurface *)surface videoPath:(NSString *)videoPath logger:(nullable id<FBControlCoreLogger>)logger
{
  NSURL *fileURL = [NSURL fileURLWithPath:videoPath];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.videoencoder.simulatorkit", DISPATCH_QUEUE_SERIAL);
  logger = [logger onQueue:queue];

  FBMutableFuture<NSNull *> *finishedWriting = [FBMutableFuture future];
  SimDisplayVideoWriter *writer = [FBVideoEncoderSimulatorKit createVideoWriterForURL:fileURL mediaQueue:queue finishedWriting:finishedWriting];

  return [[self alloc] initWithRenderable:surface fileURL:fileURL mediaQueue:queue writer:writer finishedWriting:finishedWriting logger:logger];
}

+ (SimDisplayVideoWriter *)createVideoWriterForURL:(NSURL *)url mediaQueue:(dispatch_queue_t)mediaQueue finishedWriting:(FBMutableFuture<NSNull *> *)finishedWriting
{
  Class class = objc_getClass("SimDisplayVideoWriter");

  // When we don't get a callback from the VideoWriter, assume that the finishedWriting call is synchronous.
  // This means that the future that is returned from the public API will return the pre-finished future.
  if ([class respondsToSelector:@selector(videoWriterForURL:fileType:)]) {
    [finishedWriting resolveWithResult:NSNull.null];
    return [class videoWriterForURL:url fileType:@"mp4"];
  }
  // Resolve the Future when writing has finished.
  return [class videoWriterForURL:url fileType:@"mp4" completionQueue:mediaQueue completionHandler:^(NSError *error){
    // We usually get an "error", but still handle the no-error case.
    if (!error) {
      [finishedWriting resolveWithResult:NSNull.null];
    // Represents that the IO operation has been cancelled upon finishing writing
    } else if (error.code == ECANCELED) {
      [finishedWriting resolveWithResult:NSNull.null];
    // Some other error means that something bad happened.
    } else {
      [finishedWriting resolveWithError:error];
    }
  }];
}

- (instancetype)initWithRenderable:(FBFramebufferSurface *)surface fileURL:(NSURL *)fileURL mediaQueue:(dispatch_queue_t)mediaQueue writer:(SimDisplayVideoWriter *)writer finishedWriting:(FBFuture<NSNull *> *)finishedWriting logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _surface = surface;
  _logger = logger;
  _mediaQueue = mediaQueue;
  _writer = writer;
  _finishedWriting = finishedWriting;
  _startedWriting = [FBMutableFuture future];
  _videoFile = _writer.videoFile;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"SimulatorKit Encoder %@", self.writer];
}

#pragma mark Public

+ (BOOL)isSupported
{
  return objc_getClass("SimDisplayVideoWriter") != nil;
}

- (FBFuture<NSNull *> *)startRecording
{
  return [FBFuture onQueue:self.mediaQueue resolve:^{
    return [self startRecordingNow];
  }];
}

- (FBFuture<NSNull *> *)stopRecording
{
  return [FBFuture onQueue:self.mediaQueue resolve:^{
    return [self stopRecordingNow];
  }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)startRecordingNow
{
  // Don't hit an assertion because we write twice.
  if (self.writer.startedWriting) {
    return [[FBSimulatorError
      describeFormat:@"Cannot start recording, the writer has started writing."]
      failFuture];
  }
  // Don't start twice.
  if (self.startedWriting.hasCompleted) {
    return [[FBSimulatorError
      describeFormat:@"Cannot start recording, we requested to start writing once."]
      failFuture];
  }

  // Start for real. -[SimDisplayVideoWriter startWriting]
  // must be called before sending a surface and damage rect.
  [self.logger log:@"Start Writing in Video Writer"];
  [self.writer startWriting];
  [self.logger log:@"Attaching Consumer in Video Writer"];
  IOSurfaceRef surface = [self.surface attachConsumer:self onQueue:self.mediaQueue];
  if (surface) {
    dispatch_async(self.mediaQueue, ^{
      [self didChangeIOSurface:surface];
    });
  }

  // Return the future that we've wrapped.
  return self.startedWriting;
}

- (FBFuture<NSNull *> *)stopRecordingNow
{
  // Don't hit an assertion because we're not started.
  if (!self.writer.startedWriting) {
    return [[FBSimulatorError
      describeFormat:@"Cannot stop recording, the writer has not started writing."]
      failFuture];
  }
  // If we've resolved already, we've called stop twice.
  if (self.finishedWriting.hasCompleted) {
    return [[FBSimulatorError
      describeFormat:@"Cannot stop recording, we've requested to stop recording once."]
      failFuture];
  }

  // Detach the Consumer first, we don't want to send any more Damage Rects.
  // If a Damage Rect send races with finishWriting, a crash can occur.
  [self.logger log:@"Detaching Consumer in Video Writer"];
  [self.surface detachConsumer:self];
  // Now there are no more incoming rects, tear down the video encoding.
  [self.logger log:@"Finishing Writing in Video Writer"];
  [self.writer finishWriting];

  // Return the future that we've wrapped.
  return self.finishedWriting;
}

#pragma mark FBFramebufferConsumable

- (void)didChangeIOSurface:(IOSurfaceRef)surface
{
  if (!surface) {
    [self.logger log:@"IOSurface Removed"];
    [self.writer didChangeIOSurface:NULL];
    return;
  }
  [self.logger logFormat:@"IOSurface for Encoder %@ changed to %@", self, surface];
  [self.startedWriting resolveWithResult:NSNull.null];
  if (FBXcodeConfiguration.isXcode9OrGreater) {
    [self.writer didChangeIOSurface:(__bridge id) surface];
  } else {
    xpc_object_t xpcSurface = IOSurfaceCreateXPCObject(surface);
    [self.writer didChangeIOSurface:xpcSurface];
  }
}

- (void)didReceiveDamageRect:(CGRect)rect
{
  [self.writer didReceiveDamageRect:rect];
}

- (NSString *)consumerIdentifier
{
  return self.writer.consumerIdentifier;
}

@end
