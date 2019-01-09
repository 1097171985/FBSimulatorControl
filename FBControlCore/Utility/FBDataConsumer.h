/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A consumer of NSData.
 */
@protocol FBDataConsumer <NSObject>

/**
 Consumes the provided binary data.

 @param data the data to consume.
 */
- (void)consumeData:(NSData *)data;

/**
 Consumes an EOF.
 */
- (void)consumeEndOfFile;

@end

/**
 A consumer of dispatch_data.
 */
@protocol FBDispatchDataConsumer <NSObject>

/**
 Consumes the provided binary data.

 @param data the data to consume.
 */
- (void)consumeData:(dispatch_data_t)data;

/**
 Consumes an EOF.
 */
- (void)consumeEndOfFile;

@end

/**
 A specialization of a FBDataConsumer that can expose lifecycle with a Future.
 */
@protocol FBDataConsumerLifecycle <FBDataConsumer>

/**
 A Future that resolves when an EOF has been recieved.
 This is helpful for ensuring that all consumer lines have been drained.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNull *> *eofHasBeenReceived;

@end

/**
 The Non-mutating methods of a line reader.
 */
@protocol FBAccumulatingLineBuffer <FBDataConsumerLifecycle>

/**
 Obtains a copy of the current output data.
 */
- (NSData *)data;

/**
 Obtains a copy of the current output data.
 */
- (NSArray<NSString *> *)lines;

@end

/**
 The Mutating Methods of a line reader.
 */
@protocol FBConsumableLineBuffer <FBDataConsumerLifecycle, FBAccumulatingLineBuffer>

/**
 Consume the remainder of the buffer available, returning it as Data.
 This will flush the entirity of the buffer.
 */
- (nullable NSData *)consumeCurrentData;

/**
 Consume the remainder of the buffer available, returning it as a String.
 This will flush the entirity of the buffer.
 */
- (nullable NSString *)consumeCurrentString;

/**
 Consume a line if one is available, returning it as Data.
 This will flush the buffer of the lines that are consumed.
 */
- (nullable NSData *)consumeLineData;

/**
 Consume a line if one is available, returning it as a String.
 This will flush the buffer of the lines that are consumed.
 */
- (nullable NSString *)consumeLineString;

@end

/**
 Adapts a NSData consumer to a dispatch_data consumer to.
 */
@interface FBDataConsumerAdaptor : NSObject

/**
 Adapts a NSData consumer to a dispatch_data consumer.

 @param consumer the consumer to adapt.
 @return a dispatch_data consumer.
 */
+ (id<FBDispatchDataConsumer>)dispatchDataConsumerForDataConsumer:(id<FBDataConsumer>)consumer;

/**
 Adapts a NSData consumer to a dispatch_data consumer.

 @param consumer the consumer to adapt.
 @return a NSData consumer.
 */
+ (id<FBDataConsumer>)dataConsumerForDispatchDataConsumer:(id<FBDispatchDataConsumer>)consumer;

/**
 Converts dispatch_data to NSData.
 Note that this will copy data if the underlying dispatch data is non-contiguous.

 @param dispatchData the data to adapt.
 @return NSData from the dispatchData.
 */
+ (NSData *)adaptDispatchData:(dispatch_data_t)dispatchData;

/**
 Converts dispatch_data to NSData.
 Note that this will copy data if the underlying dispatch data is non-contiguous.

 @param data the NSData to adapt.
 @return NSData from the dispatchData.
 */
+ (dispatch_data_t)adaptNSData:(NSData *)data;

@end

/**
 Implementations of a line buffers.
 This can then be consumed based on lines/strings.
 Writes and reads are fully synchronized.
 */
@interface FBLineBuffer : NSObject

/**
 A line buffer that is only mutated through consuming data.

 @return a FBLineBuffer implementation.
 */
+ (id<FBAccumulatingLineBuffer>)accumulatingBuffer;

/**
 A line buffer that is only mutated through consuming data.

 @return a FBLineBuffer implementation.
 */
+ (id<FBAccumulatingLineBuffer>)accumulatingBufferForMutableData:(NSMutableData *)data;

/**
 A line buffer that is appended to by consuming data and can be drained.

 @return a FBConsumableLineBuffer implementation.
 */
+ (id<FBConsumableLineBuffer>)consumableBuffer;

@end

/**
 A Reader of Text Data, calling the callback when a full line is available.
 */
@interface FBLineDataConsumer : NSObject <FBDataConsumer, FBDataConsumerLifecycle>

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered synchronously.

 @param consumer the block to call when a line has been consumed.
 @return a new Line Reader.
 */
+ (instancetype)synchronousReaderWithConsumer:(void (^)(NSString *))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered asynchronously to a private queue.

 @param consumer the block to call when a line has been consumed.
 @return a new Line Reader.
 */
+ (instancetype)asynchronousReaderWithConsumer:(void (^)(NSString *))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered asynchronously to the given queue.

 @param queue the queue to call the consumer from.
 @param consumer the block to call when a line has been consumed.
 @return a new Line Reader.
 */
+ (instancetype)asynchronousReaderWithQueue:(dispatch_queue_t)queue consumer:(void (^)(NSString *))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered as data asynchronously to the given queue.

 @param queue the queue to call the consumer from.
 @param consumer the block to call when a line has been consumed.
 @return a new Line Reader.
 */
+ (instancetype)asynchronousReaderWithQueue:(dispatch_queue_t)queue dataConsumer:(void (^)(NSData *))consumer;

@end

@protocol FBControlCoreLogger;

/**
 A consumer that does nothing with the data.
 */
@interface FBLoggingDataConsumer : NSObject <FBDataConsumer>

/**
 The Designated Initializer
 */
+ (instancetype)consumerWithLogger:(id<FBControlCoreLogger>)logger;

/**
 The wrapped logger.
 */
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

/**
 A Composite Consumer.
 */
@interface FBCompositeDataConsumer : NSObject <FBDataConsumer, FBDataConsumerLifecycle>

/**
 A Consumer of Consumers.

 @param consumers the consumers to compose.
 @return a new consumer.
 */
+ (instancetype)consumerWithConsumers:(NSArray<id<FBDataConsumer>> *)consumers;

@end

/**
 A consumer that does nothing with the data.
 */
@interface FBNullDataConsumer : NSObject <FBDataConsumer>

@end

NS_ASSUME_NONNULL_END
