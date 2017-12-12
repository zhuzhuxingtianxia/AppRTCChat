//
//  VideoChatController.h
//  AppRTCChat
//
//  Created by Jion on 2017/11/20.
//  Copyright © 2017年 Jion. All rights reserved.
//
//需要设置相机访问权限，和Microphone Usage Description麦克风连接描述
#import <UIKit/UIKit.h>

@interface VideoChatController : UIViewController
@property(nonatomic,copy)NSString *roomNumber;
@end

/*
 一.扬声器有回音
 二.远程视频模糊
 
 */
