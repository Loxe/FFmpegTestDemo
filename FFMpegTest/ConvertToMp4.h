//
//  ConvertToMp4.h
//  FFMpegTest
//
//  Created by 刘健 on 2017/4/20.
//  Copyright © 2017年 刘健. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ConvertToMp4 : NSObject
-(void)procWithData:(NSData *)data;
- (void)procWithExtraData:(NSData *)spsData ppsData:(NSData *)ppsData;
//写入头信息
-(void)start;
//写入尾信息
-(void)stop;

-(void)clean;
@end
