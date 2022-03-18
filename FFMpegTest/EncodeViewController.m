//
//  EncodeViewController.m
//  FFMpegTest
//
//  Created by 刘健 on 2017/3/24.
//  Copyright © 2017年 刘健. All rights reserved.
//

#import "EncodeViewController.h"

#import <AVFoundation/AVFoundation.h>

#import "HWH264Encoder.h"

#import "ConvertToMp4.h"

@interface EncodeViewController ()<AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong) AVCaptureSession *session;

@property (nonatomic, strong) AVCaptureConnection *videoConnection;

@property (nonatomic, copy) dispatch_queue_t videoQueue;
@property (nonatomic, copy) dispatch_queue_t audioQueue;

@property (nonatomic, strong) ConvertToMp4 *Mp4Writer;

@end

@implementation EncodeViewController

- (void)initializeView {
    UIButton *stop = [UIButton buttonWithType:UIButtonTypeCustom];
    [stop setFrame:CGRectMake(100, 100, 100, 100)];
    [stop setBackgroundColor:[UIColor redColor]];
    [stop setTitle:@"stop" forState:UIControlStateNormal];
    [stop addTarget:self action:@selector(stopVideoCapture) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:stop];
    
    [self Mp4Writer];
    __weak typeof(self) weakself = self;
    [HWH264Encoder sharedInstance].h264ConversionComplete = ^(NSData *data) {
        [weakself.Mp4Writer procWithData:data];
    };
    [HWH264Encoder sharedInstance].h264ExtraDataComplete = ^(NSData *spsData,NSData *ppsData) {
        [weakself.Mp4Writer procWithExtraData:spsData ppsData:ppsData];
    };
}

- (void)stopVideoCapture {
    [self.session stopRunning];
    [self.Mp4Writer stop];
    [self.Mp4Writer clean];
}

#pragma mark set session
- (void)setSession {
    
    AVCaptureDevice *videoDevice = [self getDeviceAccordingPosition:AVCaptureDevicePositionBack];
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
    
    if ([self.session canAddInput:videoInput]) {
        [self.session addInput:videoInput];
    }
    if ([self.session canAddInput:audioInput]) {
        [self.session addInput:audioInput];
    }
    
    AVCaptureAudioDataOutput *audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    if ([self.session canAddOutput:audioOutput]) {
        [self.session addOutput:audioOutput];
        _audioQueue = dispatch_queue_create("audioqueue", DISPATCH_QUEUE_SERIAL);
        [audioOutput setSampleBufferDelegate:self queue:_audioQueue];
    }
    
    if ([self.session canAddOutput:videoOutput]) {
        [self.session addOutput:videoOutput];
        [videoOutput setVideoSettings:@{(NSString *)kCVPixelBufferPixelFormatTypeKey :[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]}];
        _videoQueue = dispatch_queue_create("videoququ", DISPATCH_QUEUE_SERIAL);
        [videoOutput setSampleBufferDelegate:self queue:_videoQueue];
        _videoConnection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
    }
    
    AVCaptureVideoPreviewLayer *preview = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    preview.frame = [UIScreen mainScreen].bounds;
    [self.view.layer insertSublayer:preview atIndex:0];
    
    [self.session startRunning];
    
}

#pragma mark AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (connection == _videoConnection) {
        [[HWH264Encoder sharedInstance] convertSampleBufferToH264:sampleBuffer];
        
//        [self.Mp4Writer procWithData:[self convertVideoSampleBufferToYUVData:sampleBuffer]];
    }else{
        
    }
}



#pragma mark utils
- (AVCaptureDevice *)getDeviceAccordingPosition:(AVCaptureDevicePosition)position {
    NSArray *videos = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in videos) {
        if (device.position == position) {
            return device;
        }
    }
    return nil;
}

- (NSData *)convertVideoSampleBufferToYUVData:(CMSampleBufferRef)sampleBuffer {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    size_t pixelWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t pixelHeight = CVPixelBufferGetHeight(pixelBuffer);
    size_t y_size = pixelWidth * pixelHeight;
    size_t uv_size = y_size * 0.5;
    size_t *yuv_frame = malloc(y_size + uv_size);
    
    uint8_t *y_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    memcpy(yuv_frame, y_frame, y_size);
    
    uint8_t *uv_frame = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    memcpy(yuv_frame, uv_frame, uv_size);
    
    NSData *data = [NSData dataWithBytesNoCopy:yuv_frame length:y_size + uv_size];
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    return data;
}

- (NSData *)convertAudioSampleBufferToPCMData:(CMSampleBufferRef)sampleBuffer {
    NSInteger audioDataSize = CMSampleBufferGetTotalSampleSize(sampleBuffer);
    int8_t *audio_frame = malloc((uint32_t)audioDataSize);
    CMBlockBufferRef audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    CMBlockBufferCopyDataBytes(audioBuffer, 0, audioDataSize, audio_frame);
    NSData *data = [NSData dataWithBytesNoCopy:audio_frame length:audioDataSize];
    return data;
}


#pragma mark get
- (AVCaptureSession *)session {
    if (!_session) {
        _session = [[AVCaptureSession alloc] init];
    }
    return _session;
}

- (ConvertToMp4 *)Mp4Writer {
    if (!_Mp4Writer) {
        _Mp4Writer = [[ConvertToMp4 alloc] init];
        [_Mp4Writer start];
    }
    return _Mp4Writer;
}

#pragma mark life circle

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setSession];
    [self initializeView];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
 #pragma mark - Navigation
 
 // In a storyboard-based application, you will often want to do a little preparation before navigation
 - (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
 // Get the new view controller using [segue destinationViewController].
 // Pass the selected object to the new view controller.
 }
 */

@end


