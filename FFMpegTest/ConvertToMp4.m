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
    avPacket.data = (uint8_t *)[data bytes];
    avPacket.size = (int)data.length;
    avPacket.pos = -1;
    ret = av_interleaved_write_frame(outfmt_ctx, &avPacket);//写入（Write）
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

- (void)procWithExtraData:(NSData *)extraData {
    int extradataSize = (int)extraData.length;
    void *extradata = (void*)extraData.bytes;
    AVCodecContext* video_codec_ctx_ = video_stream->codec;
    video_codec_ctx_->extradata = (uint8_t*)malloc(extraData.length);
    memset(video_codec_ctx_->extradata, 0, extraData.length);
    memcpy(video_codec_ctx_->extradata, extradata, extraData.length);
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
    if (outfmt_ctx->oformat->flags & AVFMT_GLOBALHEADER)
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
    //写文件头（Write file header）
    ret = avformat_write_header(outfmt_ctx, NULL);
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
