// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBFileReader.h"

#import "FBControlCoreError.h"

@interface FBFileReader ()

@property (nonatomic, strong, readonly) id<FBFileConsumer> consumer;
@property (nonatomic, strong, readonly) dispatch_queue_t readQueue;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *stoppedFuture;

@property (nonatomic, strong, nullable, readwrite) NSFileHandle *fileHandle;
@property (nonatomic, strong, nullable, readwrite) dispatch_io_t io;

@end

@implementation FBFileReader

#pragma mark Initializers

+ (instancetype)readerWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBFileConsumer>)consumer
{
  return [[self alloc] initWithFileHandle:fileHandle consumer:consumer];
}

+ (nullable instancetype)readerWithFilePath:(NSString *)filePath consumer:(id<FBFileConsumer>)consumer error:(NSError **)error
{
  NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:filePath];
  if (!handle) {
    return [[FBControlCoreError describeFormat:@"Failed to open file for reading: %@", filePath] fail:error];
  }
  return [self readerWithFileHandle:handle consumer:consumer];
}

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBFileConsumer>)consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileHandle = fileHandle;
  _consumer = consumer;
  _readQueue = dispatch_queue_create("com.facebook.fbxctest.multifilereader", DISPATCH_QUEUE_SERIAL);
  _stoppedFuture = [FBMutableFuture.future onQueue:_readQueue notifyOfCompletion:^(FBFuture *_) {
    [consumer consumeEndOfFile];
  }];

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)startReading
{
  if (self.io) {
    return [[FBControlCoreError
      describeFormat:@"Could not start reading read of %@ has started", self.fileHandle]
      failFuture];
  }

  // Get locals to be captured by the read, rather than self.
  NSFileHandle *fileHandle = self.fileHandle;
  id<FBFileConsumer> consumer = self.consumer;
  FBMutableFuture<NSNull *> *doneFuture = self.stoppedFuture;

  // If there is an error creating the IO Object, the errorCode will be delivered asynchronously.
  self.io = dispatch_io_create(DISPATCH_IO_STREAM, fileHandle.fileDescriptor, self.readQueue, ^(int errorCode) {
    if (errorCode == 0) {
      [doneFuture resolveWithResult:NSNull.null];
    } else {
      NSError *error = [[FBControlCoreError describeFormat:@"IO Channel closed with error code %d", errorCode] build];
      [doneFuture resolveWithError:error];
    }
  });
  if (!self.io) {
    return [[FBControlCoreError
      describeFormat:@"A IO Channel could not be created for fd %d", fileHandle.fileDescriptor]
      failFuture];
  }

  // Report partial results with as little as 1 byte read.
  dispatch_io_set_low_water(self.io, 1);
  dispatch_io_read(self.io, 0, SIZE_MAX, self.readQueue, ^(bool done, dispatch_data_t dispatchData, int errorCode) {
    if (dispatchData != NULL) {
      const void *buffer;
      size_t size;
      __unused dispatch_data_t map = dispatch_data_create_map(dispatchData, &buffer, &size);
      NSData *data = [NSData dataWithBytes:buffer length:size];
      [consumer consumeData:data];
    }
  });
  return [FBFuture futureWithResult:NSNull.null];
}

- (FBFuture<NSNull *> *)stopReading
{
  // Return early if we've already stopped.
  if (!self.io) {
    return [[FBControlCoreError
      describe:@"File Handle is not open for reading, you should call 'startReading' first"]
      failFuture];
  }

  // Return the future after dispatching to the main queue.
  dispatch_io_close(self.io, DISPATCH_IO_STOP);
  self.fileHandle = nil;
  self.io = nil;

  return self.stoppedFuture;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.stoppedFuture onQueue:self.readQueue notifyOfCancellation:^(id _) {
    [self stopReading];
  }];
}

- (BOOL)startReadingWithError:(NSError **)error
{
  FBFuture *future = [self startReading];
  if (future.error) {
    return [FBControlCoreError failBoolWithError:future.error errorOut:error];
  }
  return YES;
}

- (BOOL)stopReadingWithError:(NSError **)error
{
  FBFuture *future = [self stopReading];
  if (future.error) {
    return [FBControlCoreError failBoolWithError:future.error errorOut:error];
  }
  return YES;
}

@end
