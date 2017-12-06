/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBPipeReader.h"

#import "FBFileReader.h"
#import "FBFileConsumer.h"

@interface FBPipeReader ()

@property (nonatomic, strong, readwrite) FBFileReader *reader;

@end

@implementation FBPipeReader

#pragma mark Initializers

+ (instancetype)pipeReaderWithConsumer:(id<FBFileConsumer>)consumer
{
  NSPipe *pipe = [NSPipe pipe];
  FBFileReader *reader = [FBFileReader readerWithFileHandle:pipe.fileHandleForReading consumer:consumer];
  return [[self alloc] initWithPipe:pipe reader:reader];
}

- (instancetype)initWithPipe:(NSPipe *)pipe reader:(FBFileReader *)reader
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _pipe = pipe;
  _reader = reader;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)startReading;
{
  return [self.reader startReading];
}

- (FBFuture<NSNull *> *)stopReading
{
  return self.reader.stopReading;
}

@end
