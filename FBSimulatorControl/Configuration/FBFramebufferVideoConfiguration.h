/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBDebugDescribeable.h>
#import <FBSimulatorControl/FBJSONSerializationDescribeable.h>

@class FBDiagnostic;

/**
 A Configuration Value for FBFramebufferVideo.
 */
@interface FBFramebufferVideoConfiguration : NSObject <NSCoding, NSCopying, FBJSONSerializationDescribeable, FBDebugDescribeable>

/**
 The Diagnostic Value to determine the video path.
 */
@property (nonatomic, copy, readonly) FBDiagnostic *diagnostic;

/**
 YES if the Video Component should automatically record when the first frame comes in.
 */
@property (nonatomic, assign, readonly) BOOL autorecord;

/**
 The Timescale used in Video Encoding.
 */
@property (nonatomic, assign, readonly) CMTimeScale timescale;

/**
 The Rounding Method used for Video Frames.
 */
@property (nonatomic, assign, readonly) CMTimeRoundingMethod roundingMethod;

/**
 The FileType of the Video.
 */
@property (nonatomic, copy, readonly) NSString *fileType;

#pragma mark Defaults & Initializers

/**
 The Default Value of FBFramebufferVideoConfiguration.
 Uses Reasonable Defaults.
 */
+ (instancetype)defaultConfiguration;

/**
 The Default Value of FBFramebufferVideoConfiguration.
 Use this in preference to 'defaultConfiguration' if video encoding is problematic.
 */
+ (instancetype)prudentConfiguration;

/**
 Creates and Returns a new FBFramebufferVideoConfiguration Value with the provided parameters.

 @param diagnostic The Diagnostic Value to determine the video path
 @param autorecord YES if the Video Component should automatically record when the first frame comes in.
 @param timescale The Timescale used in Video Encoding.
 @param roundingMethod The Rounding Method used for Video Frames.
 @param fileType The FileType of the Video.
 @return a FBFramebufferVideoConfiguration instance.
 */
+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic autorecord:(BOOL)autorecord timescale:(CMTimeScale)timescale roundingMethod:(CMTimeRoundingMethod)roundingMethod fileType:(NSString *)fileType;

#pragma mark Diagnostics

+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic;
- (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic;

#pragma mark Autorecord

- (instancetype)withAutorecord:(BOOL)autorecord;
+ (instancetype)withAutorecord:(BOOL)autorecord;

#pragma mark Timescale

- (instancetype)withTimescale:(CMTimeScale)timescale;
+ (instancetype)withTimescale:(CMTimeScale)timescale;

#pragma mark Rounding

- (instancetype)withRoundingMethod:(CMTimeRoundingMethod)roundingMethod;
+ (instancetype)withRoundingMethod:(CMTimeRoundingMethod)roundingMethod;

#pragma mark File Type

- (instancetype)withFileType:(NSString *)fileType;
+ (instancetype)withFileType:(NSString *)fileType;

@end
