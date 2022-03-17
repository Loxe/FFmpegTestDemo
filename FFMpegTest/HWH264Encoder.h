//
//  HWH264Encoder.h
//  FFMpegTest
//
//  Created by 刘健 on 2017/4/7.
//  Copyright © 2017年 刘健. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface HWH264Encoder : NSObject

@property (nonatomic, copy) void (^h264ConversionComplete)(NSData *data);
@property (nonatomic, copy) void (^h264ExtraDataComplete)(NSData *extraData);

+ (instancetype)sharedInstance;

- (void)convertSampleBufferToH264:(CMSampleBufferRef)sampleBuffer;

@end
