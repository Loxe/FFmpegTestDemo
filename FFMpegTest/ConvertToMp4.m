//
//  ConvertToMp4.m
//  FFMpegTest
//
//  Created by 刘健 on 2017/4/20.
//  Copyright © 2017年 刘健. All rights reserved.
//

#import "ConvertToMp4.h"
#include <libavformat/avformat.h>
#include <libavutil/mathematics.h>
#include <libavcodec/avcodec.h>

int WIDTH=1280;
int HEIGHT=720;
int FPS=30;
int BITRATE=16*1000;

@interface ConvertToMp4 ()
{
    //Input AVFormatContext and Output AVFormatContext
    AVOutputFormat *outFormat;
    AVFormatContext *outfmt_ctx;
    AVStream *video_stream;
    NSString *movBasePath;
    NSString *filePath;
}
@end
#define H264_NALU_TYPE_NON_IDR_PICTURE                                  1
#define H264_NALU_TYPE_IDR_PICTURE                                      5
#define H264_NALU_TYPE_SEQUENCE_PARAMETER_SET                           7
#define H264_NALU_TYPE_PICTURE_PARAMETER_SET                            8
#define H264_NALU_TYPE_SEI                                              6
@implementation ConvertToMp4
-(id)init
{
    self = [super init];
    if (self)
    {
        [self setup];
    }
    return self;
}
-(void)setup
{
    movBasePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
}

//保存帧数据
-(void)procWithData:(NSData *)data
{
    
    int ret;
    AVPacket avPacket;
    av_init_packet(&avPacket);
    uint8_t *dataBytes = (uint8_t *)data.bytes;
    int dataBytesSize = data.length;
    int nalu_type = (dataBytes[4] & 0x1F);
    if (nalu_type == H264_NALU_TYPE_SEQUENCE_PARAMETER_SET) {
    } else {
        if (nalu_type == H264_NALU_TYPE_IDR_PICTURE || nalu_type == H264_NALU_TYPE_SEI) {
            
            if(dataBytes[0] == 0x00 && dataBytes[1] == 0x00 &&
               dataBytes[2] == 0x00 && dataBytes[3] == 0x01){
                dataBytesSize -= 4;
                dataBytes[0] = ((dataBytesSize) >> 24) & 0x00ff;
                dataBytes[1] = ((dataBytesSize) >> 16) & 0x00ff;
                dataBytes[2] = ((dataBytesSize) >> 8) & 0x00ff;
                dataBytes[3] = ((dataBytesSize)) & 0x00ff;
            }
            
            avPacket.flags = AV_PKT_FLAG_KEY;
            video_stream->codec->frame_number++;
        } else {
            if(dataBytes[0] == 0x00 && dataBytes[1] == 0x00 &&
               dataBytes[2] == 0x00 && dataBytes[3] == 0x01){
                dataBytesSize -= 4;
                dataBytes[0] = ((dataBytesSize ) >> 24) & 0x00ff;
                dataBytes[1] = ((dataBytesSize ) >> 16) & 0x00ff;
                dataBytes[2] = ((dataBytesSize ) >> 8) & 0x00ff;
                dataBytes[3] = ((dataBytesSize )) & 0x00ff;
            }
            
            avPacket.flags = 0;
                    video_stream->codec->frame_number++;
        }
        
    }
    
    

    avPacket.data = (uint8_t *)dataBytes;
    avPacket.size = (int)data.length;
    avPacket.pos = -1;
    if (ret < 0)
    {
        NSLog(@ "Error muxing packet\n");
    }
    //Write
    if (av_interleaved_write_frame(outfmt_ctx, &avPacket) < 0)
    {
        NSLog(@ "Error muxing packet\n");
    }
    av_free_packet(&avPacket);
}

- (void)procWithExtraData:(NSData *)spsData ppsData:(NSData *)ppsData {
    uint8_t* spsFrame = (uint8_t *)spsData.bytes;
    uint8_t* ppsFrame = (uint8_t *)ppsData.bytes;
    
    int spsFrameLen = spsData.length;
    int ppsFrameLen = ppsData.length;
    AVCodecContext *c = video_stream->codec;
    int extradata_len = 8 + spsFrameLen - 4 + 1 + 2 + ppsFrameLen - 4;
    c->extradata = (uint8_t*) av_mallocz(extradata_len);
    c->extradata_size = extradata_len;
    c->extradata[0] = 0x01;
    c->extradata[1] = spsFrame[4 + 1];
    c->extradata[2] = spsFrame[4 + 2];
    c->extradata[3] = spsFrame[4 + 3];
    c->extradata[4] = 0xFC | 3;
    c->extradata[5] = 0xE0 | 1;
    int tmp = spsFrameLen - 4;
    c->extradata[6] = (tmp >> 8) & 0x00ff;
    c->extradata[7] = tmp & 0x00ff;
    int i = 0;
    for (i = 0; i < tmp; i++)
        c->extradata[8 + i] = spsFrame[4 + i];
    c->extradata[8 + tmp] = 0x01;
    int tmp2 = ppsFrameLen - 4;
    c->extradata[8 + tmp + 1] = (tmp2 >> 8) & 0x00ff;
    c->extradata[8 + tmp + 2] = tmp2 & 0x00ff;
    for (i = 0; i < tmp2; i++)
        c->extradata[8 + tmp + 3 + i] = ppsFrame[4 + i];
    AVDictionary* opts = NULL;
    
    av_dict_set(&opts, "movflags", "frag_keyframe+empty_moov+faststart", 0);
    int ret = avformat_write_header(outfmt_ctx, &opts);

}

//写入头信息
-(void)start
{
    int ret;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSCalendar *curCalendar = [NSCalendar currentCalendar];
    NSUInteger unitFlags = NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit;
    NSDateComponents *dateComponents = [curCalendar components:unitFlags fromDate:[NSDate date]];
    filePath = [movBasePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%ld-%ld-%ld.mp4",(long)dateComponents.hour, (long)dateComponents.minute, (long)dateComponents.second ]];
    [fileManager createFileAtPath:filePath contents:nil attributes:nil];
    const char *out_filename = [filePath UTF8String];//URL 路径
    av_register_all();//注册所有容器格式和CODEC
    avformat_alloc_output_context2(&outfmt_ctx, NULL, "mp4", out_filename);// 初始化一个用于输出的AVFormatContext结构体
    if (!outfmt_ctx)
    {
        NSLog(@ "Could not create output context\n");
        //        ret = AVERROR_UNKNOWN;
    }
    outFormat = outfmt_ctx->oformat;
    AVCodec *codec = avcodec_find_decoder(AV_CODEC_ID_H264);//查找对应的解码器
    AVStream *out_stream = avformat_new_stream(outfmt_ctx, codec);//创建输出码流的AVStream
    if (!out_stream)
    {
        NSLog(@ "Failed allocating output stream\n");
        //        ret = AVERROR_UNKNOWN;
    }
    
    ret = avcodec_copy_context(out_stream->codec, avcodec_alloc_context3(codec));//拷贝输入视频码流的AVCodecContex的数值t到输出视频的AVCodecContext。
    if (ret < 0)
    {
        NSLog(@ "Failed to copy context from input to output stream codec context\n");
    }
    out_stream->codec->pix_fmt = AV_PIX_FMT_YUV420P;//支持的像素格式
    out_stream->codec->flags = CODEC_FLAG_GLOBAL_HEADER;
    out_stream->codec->width = WIDTH;
    out_stream->codec->height = HEIGHT;
    out_stream->codec->time_base = (AVRational){1,FPS};
    out_stream->codec->gop_size = FPS;
    out_stream->codec->bit_rate = BITRATE;
    out_stream->codec->codec_tag = 0;
    if (outFormat->flags & AVFMT_GLOBALHEADER)
    {
        out_stream->codec->flags |= CODEC_FLAG_GLOBAL_HEADER;
    }
    //    AVBitStreamFilterContext \*avFilter = av_bitstream_filter_init("h264_mp4toannexb");
    //    out_stream->codec->extradata_size = size;
    //    out_stream->codec->extradata = (uint8_t \*)av_malloc(size + FF_INPUT_BUFFER_PADDING_SIZE);
    //输出一下格式------------------
    av_dump_format(outfmt_ctx, 0, out_filename, 1);
    if (!(outFormat->flags & AVFMT_NOFILE))
    {
        ret = avio_open(&outfmt_ctx->pb, out_filename, AVIO_FLAG_WRITE);
        if (ret < 0)
        {
            NSLog(@ "Could not open output file '%s'", out_filename);
        }
    }
//    AVDictionary* opts = NULL;
//
//    av_dict_set(&opts, "movflags", "frag_keyframe+empty_moov+faststart", 0);
//    //写文件头（Write file header）
//    ret = avformat_write_header(outfmt_ctx, &opts);
    if (ret < 0)
    {
        NSLog(@ "Error occurred when opening output file\n");
    }
    video_stream = out_stream;
}

//写入尾信息
-(void)stop
{
    av_write_trailer(outfmt_ctx);
}

-(void)clean
{
    if (outfmt_ctx && !(outFormat->flags & AVFMT_NOFILE))
    {
        avio_close(outfmt_ctx->pb);
    }
    avformat_free_context(outfmt_ctx);
}
@end
