
//
//  HWH264Encoder.m
//  FFMpegTest
//
//  Created by 刘健 on 2017/4/7.
//  Copyright © 2017年 刘健. All rights reserved.
//

#import "HWH264Encoder.h"
#import <VideoToolbox/VideoToolbox.h>

@interface HWH264Encoder()
{
    int frameID;
    VTCompressionSessionRef encodingSession;
    NSFileHandle *fileHnadle;
}
@property (nonatomic, strong) dispatch_queue_t encodeQueue;
@property (nonatomic, strong) AVAssetWriterInput *videoInput;



@end

@implementation HWH264Encoder

+ (instancetype)sharedInstance {
    static HWH264Encoder *encoder = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        encoder = [[HWH264Encoder alloc] init];
        [encoder initialVideoToolBox];
    });
    return encoder;
}

void didCompressH264(void * CM_NULLABLE outputCallbackRefCon, void * CM_NULLABLE sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,CM_NULLABLE CMSampleBufferRef sampleBuffer ) {
    if (status != noErr) {
        NSLog(@"compress h264 failed");
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"compress data is not ready");
        return;
    }
    HWH264Encoder *encoder = (__bridge HWH264Encoder *)outputCallbackRefCon;
    
    CFDictionaryRef infoRef = CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0);
    bool keyFrame = !CFDictionaryContainsKey(infoRef, kCMSampleAttachmentKey_NotSync);
    // 判断当前帧是否为关键帧
    if (keyFrame) {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t sparameterLength, sparameterCount;
        const uint8_t *sparameterPointer;
        OSStatus status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterPointer, &sparameterLength, &sparameterCount, 0);
        if (status == noErr) {
            size_t pparameterLength, pparameterCount;
            const uint8_t *pparameterPointer;
            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterPointer, &pparameterLength, &pparameterCount, 0);
            if (status == noErr) {
                NSData *sps = [NSData dataWithBytes:sparameterPointer length:sparameterLength];
                NSData *pps = [NSData dataWithBytes:pparameterPointer length:pparameterLength];
                if (encoder) {
                    // 保存sps和pps数据
                    [encoder gotPpsSps:pps sps:sps];
                }
            }
            
            //
            CMFormatDescriptionRef description = CMSampleBufferGetFormatDescription(sampleBuffer);
            CFDictionaryRef extensions = CMFormatDescriptionGetExtensions(description);
            NSDictionary *extensionsDic = (__bridge NSDictionary*)extensions;
            NSData *extraDataOC = [[extensionsDic objectForKey:@"SampleDescriptionExtensionAtoms"] objectForKey:@"avcC"];
//            int extradataSize = (int)extraDataOC.length;
//            void *extradata = (void*)extraDataOC.bytes;
            if (extraDataOC!=nil) {
                encoder.h264ExtraDataComplete(extraDataOC);
            }
        }
    }
    
    // 现在开始保存视频数据
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    status = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (status == noErr) {
        size_t bufferOffset = 0;
        static const int headerLength = 4; // nalu单元前面4个字节保存的是大端模式的帧的长度
        while (bufferOffset < totalLength - headerLength) {
            // read nal unit length
            uint32_t naluLength = 0;
            memcpy(&naluLength, dataPointer + bufferOffset, headerLength);
            naluLength = CFSwapInt32BigToHost(naluLength);
            
            // read frame data
            NSData *data = [NSData dataWithBytes:dataPointer + bufferOffset + headerLength length:naluLength];
            [encoder gotEncodeData:data];
            
            // store encode data
            bufferOffset += headerLength + naluLength;
        }
    }
    
}

- (void)gotPpsSps:(NSData *)pps sps:(NSData *)sps {
    if (fileHnadle) {
        NSLog(@"got sps:%d--pps:%d", sps.length, pps.length);
        const char bytes[] = "\x00\x00\x00\x01";
        NSData *header = [NSData dataWithBytes:bytes length:(sizeof(bytes) - 1)];
        [fileHnadle writeData:header];
        [fileHnadle writeData:sps];
        [fileHnadle writeData:header];
        [fileHnadle writeData:pps];
    }
}

- (void)gotEncodeData:(NSData *)data {
    if (fileHnadle) {
        NSLog(@"got encode data: %d", data.length);
        const char bytes[] = "\x00\x00\x00\x01";
        NSData *header = [NSData dataWithBytes:bytes length:(sizeof(bytes) - 1)];
        [fileHnadle writeData:header];
        [fileHnadle writeData:data];
        NSMutableData *data_ = [NSMutableData new];
//        [data_ appendData:header];
        [data_ appendData:data];
        _h264ConversionComplete(data_);
    }
}

- (void)convertSampleBufferToH264:(CMSampleBufferRef)sampleBuffer {
    dispatch_sync(_encodeQueue, ^{
        CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        CMTime pts = CMTimeMake(frameID++, 1000);
        VTEncodeInfoFlags flags;
        OSStatus status = VTCompressionSessionEncodeFrame(encodingSession, imageBuffer, pts, kCMTimeInvalid, NULL, NULL, &flags);
        if (status != noErr) {
            NSLog(@"vtcompressionsession encode frame failed with %d", (int)status);
            VTCompressionSessionInvalidate(encodingSession);
            CFRelease(encodingSession);
            encodingSession = NULL;
            return ;
        }
        NSLog(@"vtcompressionsession encode frame successful");
    });
}


- (void)initialVideoToolBox {
    fileHnadle = [self createWriteFileHandleByfileName:@"abc.h264"];
    _encodeQueue = dispatch_queue_create(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(_encodeQueue, ^{
        frameID = 0;
        int width = 1280, height = 720;
        OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, (__bridge void *)self, &encodingSession);
        if (status != noErr) {
            NSLog(@"h264: unable to create a h264 session");
        }
        // 设置实时编码输出(避免延迟)

        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        
        // 设置关键帧(GOPsize)间隔
        int frameInterval = 40;
        CFNumberRef frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
        
        // 设置码率上限bps
        int bitRate = width * height * 3 * 4 * 4;
        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
        VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
        
        // tell the encoder ready to start
        status = VTCompressionSessionPrepareToEncodeFrames(encodingSession);
        if (status != noErr) {
            NSLog(@"compression session initialize failed");
        }
    });
}


- (NSFileHandle *)createWriteFileHandleByfileName:(NSString *)fileName {
    NSString *file = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:fileName];
    [[NSFileManager defaultManager] removeItemAtPath:file error:nil];
    [[NSFileManager defaultManager] createFileAtPath:file contents:nil attributes:nil];
    return [NSFileHandle fileHandleForWritingAtPath:file];
}

- (NSString *)getDestnationPathAtStartRecording {
    NSDateFormatter *formatter1 = [[NSDateFormatter alloc] init];
    [formatter1 setDateFormat:@"YY_MM_dd_HH_mm_ss"];
    NSString *fileName = [formatter1 stringFromDate:[NSDate date]];
    NSString *videoPath = [NSHomeDirectory() stringByAppendingFormat:@"/Documents/vedio/%@.mp4",fileName];
    return videoPath;
}

- (AVAssetWriter *)getMp4Writer {
    NSError *error = nil;
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:[NSURL URLWithString:[self getDestnationPathAtStartRecording]] fileType:AVFileTypeQuickTimeMovie error:&error];
    if (error) {
        NSLog(@"avasset writer create failed");
    }
    return writer;
}

- (AVAssetWriterInput *)videoInput {
    if (!_videoInput) {
        NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                       AVVideoCodecH264, AVVideoCodecKey,
                                       [NSNumber numberWithInt:1280], AVVideoWidthKey,
                                       [NSNumber numberWithInt:720],AVVideoHeightKey,
                                       nil];
        _videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
        _videoInput.expectsMediaDataInRealTime = YES;
    }
    return _videoInput;
}
























@end
