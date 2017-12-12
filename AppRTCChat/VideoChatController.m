//
//  VideoChatController.m
//  AppRTCChat
//
//  Created by Jion on 2017/11/20.
//  Copyright © 2017年 Jion. All rights reserved.
//

#import "VideoChatController.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <SocketRocket.h>
#import <RTCMediaStream.h>
#import <RTCPeerConnectionFactory.h>
#import <RTCPeerConnection.h>
#import <RTCPair.h>
#import <RTCMediaConstraints.h>
#import <RTCAudioTrack.h>
#import <RTCVideoTrack.h>
#import <RTCVideoCapturer.h>
#import <RTCSessionDescription.h>
#import <RTCSessionDescriptionDelegate.h>
#import <RTCEAGLVideoView.h>
#import <RTCICEServer.h>
#import <RTCVideoSource.h>
#import <RTCAVFoundationVideoSource.h>
#import <RTCICECandidate.h>

#define KScreenWidth [UIScreen mainScreen].bounds.size.width
#define KScreenHeight [UIScreen mainScreen].bounds.size.height
#define KVedioWidth KScreenWidth/3.0
#define KVedioHeight KVedioWidth*320/240

/*
 //可用的stun服务器：
 stun:stun.l.google.com:19302
 stun:stun.xten.com:3478
 stun:stun.voipbuster.com:3478
 stun:stun.voxgratia.org:3478
 stun:stun.ekiga.net:3478
 stun:stun.ideasip.com:3478
 stun:stun.schlund.de:3478
 stun:stun.voiparound.com:3478
 stun:stun.voipbuster.com:3478
 stun:stun.voipstunt.com:3478
 stun:numb.viagenie.ca:3478
 stun:stun.counterpath.com:3478
 stun:stun.gmx.net:3478
 stun:stun.bcs2005.net:3478
 stun:stun.callwithus.com:3478
 stun:stun.counterpath.net:3478
 stun:stun.internetcalls.com:3478
 stun:stun.voip.aebc.com:3478
 stun:stun.viagenie.ca:3478
 stun:stun.freeswitch.org
 */
static NSString *const RTCSTUNServerURL = @"stun:stun.freeswitch.org";
static NSString *const RTCSTUNServerURL2 = @"stun:stun.xten.com:3478";
typedef enum : NSUInteger {
    //发送者
    RoleCaller,
    //被发送者
    RoleCallee,
} Role;

@interface VideoChatController ()<SRWebSocketDelegate,RTCPeerConnectionDelegate,RTCSessionDescriptionDelegate>
{
    NSMutableDictionary *_connectionDic;
    NSMutableArray *_connectionIdArray;
    
    SRWebSocket *_socket;
    NSString *_server;
    NSString *_userId;
    
    RTCPeerConnectionFactory *_factory;
    RTCMediaStream *_localStream;
    
    Role _role;
    
    NSMutableArray *ICEServers;
}
//用于显示连接状态信息
@property(nonatomic,strong)UILabel *statusLabel;
@property(nonatomic,strong)UIButton *swichCameraBtn;
//本地摄像头追踪
@property(nonatomic,strong)RTCVideoTrack *localVideoTrack;
@property(nonatomic,strong)RTCAVFoundationVideoSource *localVideoSource;
//远程的视频追踪
@property(nonatomic,strong)NSMutableDictionary *remoteVideoTracks;
@property(nonatomic,strong)RTCEAGLVideoView *remoteVideoView;

@end

@implementation VideoChatController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor whiteColor];
    [self initData];
    
    [self buildClose];
    
    [self connectAction];
}
- (void)initData{
    
    _remoteVideoTracks = [NSMutableDictionary dictionary];
    _connectionDic = [NSMutableDictionary dictionary];
    _connectionIdArray = [NSMutableArray array];
    
    //一直保持屏幕亮
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    
}

//连接
- (void)connectAction{
   
    [self connectServer:@"192.168.5.106" port:@"3000" room:self.roomNumber];
    //加载本地视频流
    //创建点对点工厂
    if (!_factory) {
        //设置SSL传输
        [RTCPeerConnectionFactory initializeSSL];
        _factory = [[RTCPeerConnectionFactory alloc] init];
    }
    //本地视频流
    if (!_localStream) {
        //创建本地流
        [self createLocalStream];
    }
    
}
//断开连接
- (void)disConnectAction{
    [self exitRoom];
    
}
/**
 *  退出房间
 */
- (void)exitRoom
{
    _localStream = nil;
    [_connectionIdArray enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self closePeerConnection:obj];
    }];
    [_socket close];
}

//初始化socket并且连接
- (void)connectServer:(NSString *)server port:(NSString *)port room:(NSString *)room{
    _server = server;
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"ws://%@:%@",server,port]] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
    _socket = [[SRWebSocket alloc] initWithURLRequest:request];
    _socket.delegate = self;
    [_socket open];
}

#pragma mark -- SRWebSocketDelegate
- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message{
    NSLog(@"收到消息:%@",message);
    NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:[message dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:nil];
    NSString *eventName = dic[@"eventName"];
    
    //1.发送加入创建房间后的反馈
    if ([eventName isEqualToString:@"_peers"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"创建房间";
        });
        
        //得到data
        NSDictionary *dataDic = dic[@"data"];
        //得到所有的连接
        NSArray *connections = dataDic[@"connections"];
        //添加到连接数组中
        [_connectionIdArray addObjectsFromArray:connections];
        //拿到给自己分配的ID
        _userId = dataDic[@"you"];
        
        //创建连接
        [_connectionIdArray enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL * _Nonnull stop) {
            
            //根据连接ID去初始化 RTCPeerConnection 连接对象
            RTCPeerConnection *connection = [self createPeerConnection:obj];
            
            //设置这个ID对应的 RTCPeerConnection对象
            [_connectionDic setObject:connection forKey:obj];
        }];
        
        //给每一个点对点连接，都加上本地流
        [_connectionDic enumerateKeysAndObjectsUsingBlock:^(NSString *key, RTCPeerConnection *obj, BOOL * _Nonnull stop) {
            if (!_localStream)
            {
                [self createLocalStream];
            }
            [obj addStream:_localStream];
        }];
        
        //给每一个点对点连接，都去创建offer
        __weak typeof(self) weakSelf = self;
        [_connectionDic enumerateKeysAndObjectsUsingBlock:^(NSString *key, RTCPeerConnection *obj, BOOL * _Nonnull stop) {
            _role = RoleCaller;
            //添加代理
            [obj createOfferWithDelegate:weakSelf constraints:[self offerOranswerConstraint]];
        }];
        
    }
    //2.其他新人加入房间的信息
    else if ([eventName isEqualToString:@"_new_peer"]){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"新人加入";
        });
        
        NSDictionary *dataDic = dic[@"data"];
        //拿到新人的ID
        NSString *socketId = dataDic[@"socketId"];
        //再去创建一个连接
        RTCPeerConnection *peerConnection = [self createPeerConnection:socketId];
        if (!_localStream)
        {
            [self createLocalStream];
        }
        //把本地流加到连接中去
        [peerConnection addStream:_localStream];
        //连接ID新加一个
        [_connectionIdArray addObject:socketId];
        //并且设置到Dic中去
        [_connectionDic setObject:peerConnection forKey:socketId];
        
    }
    //3.新加入的人发了个表示愿意的offer
    else if ([eventName isEqualToString:@"_offer"]){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"新加入的人发了个表示愿意的offer";
        });
        
        NSDictionary *dataDic = dic[@"data"];
        NSDictionary *sdpDic = dataDic[@"sdp"];
        //拿到SDP
        NSString *sdp = sdpDic[@"sdp"];
        NSString *type = sdpDic[@"type"];
        NSString *socketId = dataDic[@"socketId"];
        
        //拿到这个点对点的连接
        RTCPeerConnection *peerConnection = [_connectionDic objectForKey:socketId];
        //根据类型和SDP 生成SDP描述对象
        RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:type sdp:sdp];
        //设置给这个点对点连接
        [peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:remoteSdp];
        
        //设置当前角色状态为被呼叫，（被发offer）
        _role = RoleCallee;
    }
    //4.接收到新加入的人发了ICE候选,（即经过ICEServer而获取到的地址）执行多次
    else if ([eventName isEqualToString:@"_ice_candidate"]){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
             self.statusLabel.text = @"接收新加入的人发了ICE";
        });
       
        
        NSDictionary *dataDic = dic[@"data"];
        NSString *socketId = dataDic[@"socketId"];
        NSString *sdpMid = dataDic[@"id"];
        NSInteger sdpMLineIndex = [dataDic[@"label"] integerValue];
        NSString *sdp = dataDic[@"candidate"];
        //生成远端网络地址对象
        RTCICECandidate *candidate = [[RTCICECandidate alloc] initWithMid:sdpMid index:sdpMLineIndex sdp:sdp];
        //拿到当前对应的点对点连接
        RTCPeerConnection *peerConnection = [_connectionDic objectForKey:socketId];
        //添加到点对点连接中
        [peerConnection addICECandidate:candidate];
    }
    //5.有人离开房间
    else if ([eventName isEqualToString:@"_remove_peer"]){
        self.statusLabel.text = @"有人离开房间";
        
        //得到socketId，关闭这个peerConnection
        NSDictionary *dataDic = dic[@"data"];
        NSString *socketId = dataDic[@"socketId"];
        [self closePeerConnection:socketId];
        
    }
    //1.
    //2.回应表示愿意的offer
    else if ([eventName isEqualToString:@"_answer"]){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"我回应表示愿意的offer";
        });
        
        NSDictionary *dataDic = dic[@"data"];
        NSDictionary *sdpDic = dataDic[@"sdp"];
        NSString *sdp = sdpDic[@"sdp"];
        NSString *type = sdpDic[@"type"];
        NSString *socketId = dataDic[@"socketId"];
        RTCPeerConnection *peerConnection = [_connectionDic objectForKey:socketId];
        RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:type sdp:sdp];
        [peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:remoteSdp];
        
    }
    //3.接收到新加入的人发了ICE候选,（即经过ICEServer而获取到的地址）执行多次
    
}
- (void)webSocketDidOpen:(SRWebSocket *)webSocket{
    NSLog(@"websocket建立成功");
    self.statusLabel.text = @"连接成功";
    //加入房间
    [self joinRoom:self.roomNumber];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error{
    NSLog(@"%s",__func__);
    NSLog(@"%ld:%@",(long)error.code, error.localizedDescription);
     self.statusLabel.text = error.localizedDescription;
}
- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean{
    NSLog(@"%s",__func__);
    NSLog(@"%ld:%@",(long)code, reason);
    self.statusLabel.text = reason ? reason : @"断开连接";
}

- (void)webSocket:(SRWebSocket *)webSocket didReceivePong:(NSData *)pongPayload{
    
}
// Return YES to convert messages sent as Text to an NSString. Return NO to skip NSData -> NSString conversion for Text messages. Defaults to YES.
- (BOOL)webSocketShouldConvertTextFrameToString:(SRWebSocket *)webSocket{
    
    return YES;
}

#pragma mark -- pritve
- (void)joinRoom:(NSString *)room {
    //如果socket是打开状态
    if (_socket.readyState == SR_OPEN)
    {
        //初始化加入房间的类型参数 room房间号
        NSDictionary *dic = @{@"eventName": @"__join", @"data": @{@"room": room}};
        
        //得到json的data
        NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
        //发送加入房间的数据
        [_socket send:data];
    }
}

//创建本地流，并且把本地流回调出去
-(void)createLocalStream{
    
    _localStream = [_factory mediaStreamWithLabel:@"ARDAMS"];
    //音频
    RTCAudioTrack *audioTrack = [_factory audioTrackWithID:@"ARDAMSa0"];
    [_localStream addAudioTrack:audioTrack];
    
    //视频
    NSArray *deviceArray = [AVCaptureDevice devicesWithMediaType: AVMediaTypeVideo];
    AVCaptureDevice *device = [deviceArray lastObject];
    //检测摄像头权限
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (authStatus == AVAuthorizationStatusDenied || authStatus == AVAuthorizationStatusRestricted) {
        NSLog(@"相机访问受限");
    }else{
        if (device) {
            /*
            RTCVideoCapturer *capturer = [RTCVideoCapturer capturerWithDeviceName:device.localizedName];
            RTCVideoSource *videoSource = [_factory videoSourceWithCapturer:capturer constraints:[self localVideoConstraints]];
             */
            
            RTCAVFoundationVideoSource *videoSource = [[RTCAVFoundationVideoSource alloc] initWithFactory:_factory constraints:[self localVideoConstraints]];
            _localVideoSource = videoSource;
            RTCVideoTrack *videoTrack = [_factory videoTrackWithID:@"ARDAMSv0" source:videoSource];
            [_localStream addVideoTrack:videoTrack];
            
            
            //显示本地流
            RTCEAGLVideoView *localVideoView = [[RTCEAGLVideoView alloc] init];
            localVideoView.frame = CGRectMake(0, 60, 375/2.0, 375/2.0*1.3);
            //标记摄像头
            localVideoView.tag = 100;
            //摄像头旋转
            localVideoView.transform = CGAffineTransformMakeScale(-1.0, 1.0);
            _localVideoTrack = [_localStream.videoTracks lastObject];
            [_localVideoTrack addRenderer:localVideoView];
            [self.view addSubview:localVideoView];
            
            NSLog(@"setLocalStream");
            
        }else{
            NSLog(@"该设备不能打开摄像头");
        }
    }
}

/**
 *  视频的相关约束
 */
- (RTCMediaConstraints *)localVideoConstraints
{
    RTCPair *maxWidth = [[RTCPair alloc] initWithKey:@"maxWidth" value:@"1280"];
    RTCPair *minWidth = [[RTCPair alloc] initWithKey:@"minWidth" value:@"640"];
    
    RTCPair *maxHeight = [[RTCPair alloc] initWithKey:@"maxHeight" value:@"960"];
    RTCPair *minHeight = [[RTCPair alloc] initWithKey:@"minHeight" value:@"480"];
    
    RTCPair *minFrameRate = [[RTCPair alloc] initWithKey:@"minFrameRate" value:@"30"];
    
    NSArray *mandatory = @[maxWidth, minWidth, maxHeight, minHeight, minFrameRate];
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatory optionalConstraints:nil];
    return constraints;
}

//创建点对点连接
- (RTCPeerConnection *)createPeerConnection:(NSString *)connectionId
{
    //如果点对点工厂为空
    if (!_factory)
    {
        //先初始化工厂
        [RTCPeerConnectionFactory initializeSSL];
        _factory = [[RTCPeerConnectionFactory alloc] init];
    }
    
    //得到ICEServer
    if (!ICEServers) {
        ICEServers = [NSMutableArray array];
    }
    /*
    [ICEServers addObject:[self defaultSTUNServer:RTCSTUNServerURL ]];
    [ICEServers addObject:[self defaultSTUNServer:RTCSTUNServerURL2]];
    NSArray *stunServer = @[@"stun:stun.l.google.com:19302",
                            @"stun:stun1.l.google.com:19302",
                            @"stun:stun2.l.google.com:19302",
                            @"stun:stun3.l.google.com:19302",
                            @"stun:stun3.l.google.com:19302",
                            @"stun:stun.ekiga.net:3478",
                            @"stun:stun.ideasip.com:3478",
                            @"stun:stun.schlund.de:3478",
                            @"stun:stun.voiparound.com:3478",
                            @"stun:stun.voipbuster.com:3478",
                            @"stun:stun.voipstunt.com:3478",
                            @"stun:stun.voxgratia.org:3478"
                            ];
    */
    
    NSArray *stunServer = @[
                      @"stun:turn.quickblox.com",
                      @"turn:turn.quickblox.com:3478?transport=udp",
                      @"turn:turn.quickblox.com:3478?transport=tcp"
                      ];
    for (NSString *url  in stunServer) {
        [ICEServers addObject:[self defaultSTUNServer:url]];
        
    }
    
    //用工厂来创建连接
    RTCPeerConnection *connection = [_factory peerConnectionWithICEServers:ICEServers constraints:[self peerConnectionConstraints] delegate:self];
    return connection;
}
- (RTCICEServer *)defaultSTUNServer:(NSString *)stunURL {
    NSURL *defaultSTUNServerURL = [NSURL URLWithString:stunURL];
    NSString *userName = [stunURL containsString:@"quickblox"] ? @"quickblox":@"";
    NSString *password = [stunURL containsString:@"quickblox"] ?@"baccb97ba2d92d71e26eb9886da5f1e0":@"";
    return [[RTCICEServer alloc] initWithURI:defaultSTUNServerURL
                                    username:userName
                                    password:password];
}

- (RTCMediaConstraints *)peerConnectionConstraints
{
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:@[[[RTCPair alloc] initWithKey:@"DtlsSrtpKeyAgreement" value:@"true"]]];
    return constraints;
}

/**
 *  设置offer/answer的约束
 */
- (RTCMediaConstraints *)offerOranswerConstraint
{
    NSMutableArray *array = [NSMutableArray array];
    RTCPair *receiveAudio = [[RTCPair alloc] initWithKey:@"OfferToReceiveAudio" value:@"true"];
    [array addObject:receiveAudio];
    
    NSString *video = @"true";
    RTCPair *receiveVideo = [[RTCPair alloc] initWithKey:@"OfferToReceiveVideo" value:video];
    [array addObject:receiveVideo];
   //回音消除
    RTCPair *echoCancellation = [[RTCPair alloc] initWithKey:@"VoiceActivityDetection" value:@"false"];
    [array addObject:echoCancellation];
    
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:array optionalConstraints:nil];
    return constraints;
}

- (NSString *)getKeyFromConnectionDic:(RTCPeerConnection *)peerConnection
{
    //find socketid by pc
    static NSString *socketId;
    [_connectionDic enumerateKeysAndObjectsUsingBlock:^(NSString *key, RTCPeerConnection *obj, BOOL * _Nonnull stop) {
        if ([obj isEqual:peerConnection])
        {
            NSLog(@"%@",key);
            socketId = key;
        }
    }];
    return socketId;
}

- (void)closePeerConnection:(NSString *)connectionId
{
    RTCPeerConnection *peerConnection = [_connectionDic objectForKey:connectionId];
    if (peerConnection)
    {
        [peerConnection close];
    }
    [_connectionIdArray removeObject:connectionId];
    [_connectionDic removeObjectForKey:connectionId];
    dispatch_async(dispatch_get_main_queue(), ^{
        //移除对方视频追踪
        [_remoteVideoTracks removeObjectForKey:connectionId];
        [self _refreshRemoteView];
    });
}

//视频显示布局
- (void)_refreshRemoteView
{
    for (RTCEAGLVideoView *videoView in self.view.subviews) {
        //本地的视频View和关闭按钮不做处理
        if (videoView.tag == 100 ||videoView.tag == 123) {
            continue;
        }
        if ([videoView isKindOfClass:[RTCEAGLVideoView class]]) {
            //其他的移除
            [videoView removeFromSuperview];
        }
        
    }
    //__block int column = 1;
    //__block int row = 0;
    //再去添加
    [_remoteVideoTracks enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, RTCVideoTrack *remoteTrack, BOOL * _Nonnull stop) {
        
        [remoteTrack addRenderer:self.remoteVideoView];
        [self.view addSubview:self.remoteVideoView];
        
        /*
        RTCEAGLVideoView *remoteVideoView = [[RTCEAGLVideoView alloc] initWithFrame:CGRectMake(column * KVedioWidth, 0, KVedioWidth, KVedioHeight)];
        [remoteTrack addRenderer:remoteVideoView];
        [self.view addSubview:remoteVideoView];
        
        //列加1
        column++;
        //一行多余3个在起一行
        if (column > 3) {
            row++;
            column = 0;
        }
         */
    }];
}


#pragma mark --RTCPeerConnectionDelegate
// Triggered when the SignalingState changed.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
 signalingStateChanged:(RTCSignalingState)stateChanged{
    NSLog(@"%s",__func__);
    NSLog(@"stateChanged = %d", stateChanged);
}

// Triggered when media is received on a new stream from remote peer.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
           addedStream:(RTCMediaStream *)stream{
    NSLog(@"%s",__func__);
    //
     NSString *uid = [self getKeyFromConnectionDic : peerConnection];
    dispatch_async(dispatch_get_main_queue(), ^{
        //缓存起来
        [_remoteVideoTracks setObject:[stream.videoTracks lastObject] forKey:uid];
        
        //开启扬声器
        [self speakerBtnAction:nil];
        [self _refreshRemoteView];
    });
    
    NSLog(@"addRemoteStream");
}

// Triggered when a remote peer close a stream.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
         removedStream:(RTCMediaStream *)stream{
    NSLog(@"%s",__func__);
}

// Triggered when renegotiation is needed, for example the ICE has restarted.
- (void)peerConnectionOnRenegotiationNeeded:(RTCPeerConnection *)peerConnection{
    NSLog(@"%s",__func__);
}

// Called any time the ICEConnectionState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
  iceConnectionChanged:(RTCICEConnectionState)newState{
    NSLog(@"%s",__func__);
    NSLog(@"newState = %d", newState);
}

// Called any time the ICEGatheringState changes.
- (void)peerConnection:(RTCPeerConnection *)peerConnection
   iceGatheringChanged:(RTCICEGatheringState)newState{
    NSLog(@"%s",__func__);
    NSLog(@"newState = %d", newState);
}

// New Ice candidate have been found.
//创建peerConnection之后，从server得到响应后调用，得到ICE 候选地址
- (void)peerConnection:(RTCPeerConnection *)peerConnection
       gotICECandidate:(RTCICECandidate *)candidate{
    NSLog(@"%s",__func__);
    //
    
    NSString *currentId = [self getKeyFromConnectionDic : peerConnection];
    
    NSDictionary *dic = @{@"eventName": @"__ice_candidate", @"data": @{@"id":candidate.sdpMid,@"label": [NSNumber numberWithInteger:candidate.sdpMLineIndex], @"candidate": candidate.sdp, @"socketId": currentId}};
    NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
    [_socket send:data];
}

// New data channel has been opened.
- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didOpenDataChannel:(RTCDataChannel*)dataChannel{
    NSLog(@"%s",__func__);
}

#pragma mark -- RTCSessionDescriptionDelegate
// Called when creating a session.
//创建了一个SDP就会被调用，（只能创建本地的）
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didCreateSessionDescription:(RTCSessionDescription *)sdp
                 error:(NSError *)error{
    NSLog(@"%s",__func__);
    NSLog(@"%@",sdp.type);
    //设置本地的SDP
    [peerConnection setLocalDescriptionWithDelegate:self sessionDescription:sdp];
}

// Called when setting a local or remote description.
//当一个远程或者本地的SDP被设置就会调用
- (void)peerConnection:(RTCPeerConnection *)peerConnection
didSetSessionDescriptionWithError:(NSError *)error{
    NSLog(@"%s",__func__);
    
    NSString *currentId = [self getKeyFromConnectionDic : peerConnection];
    
    //判断，当前连接状态为，收到了远程点发来的offer，这个是进入房间的时候，尚且没人，来人就调到这里
    if (peerConnection.signalingState == RTCSignalingHaveRemoteOffer)
    {
        //创建一个answer,会把自己的SDP信息返回出去
        [peerConnection createAnswerWithDelegate:self constraints:[self offerOranswerConstraint]];
    }
    //判断连接状态为本地发送offer
    else if (peerConnection.signalingState == RTCSignalingHaveLocalOffer)
    {
        if (_role == RoleCallee)
        {
            NSDictionary *dic = @{@"eventName": @"__answer", @"data": @{@"sdp": @{@"type": @"answer", @"sdp": peerConnection.localDescription.description}, @"socketId": currentId}};
            NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
            [_socket send:data];
        }
        //发送者,发送自己的offer
        else if(_role == RoleCaller)
        {
            NSDictionary *dic = @{@"eventName": @"__offer", @"data": @{@"sdp": @{@"type": @"offer", @"sdp": peerConnection.localDescription.description}, @"socketId": currentId}};
            NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
            [_socket send:data];
        }
    }
    else if (peerConnection.signalingState == RTCSignalingStable)
    {
        if (_role == RoleCallee)
        {
            NSDictionary *dic = @{@"eventName": @"__answer", @"data": @{@"sdp": @{@"type": @"answer", @"sdp": peerConnection.localDescription.description}, @"socketId": currentId}};
            NSData *data = [NSJSONSerialization dataWithJSONObject:dic options:NSJSONWritingPrettyPrinted error:nil];
            [_socket send:data];
        }
    }
    
}

#pragma mark -- action
-(void)closeAction{
    [self exitRoom];
    [self dismissViewControllerAnimated:YES completion:^{
        [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
        //关闭扬声器
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];

    }];
}

-(void)swichCameraAction:(UIButton*)sender{
    sender.selected = !sender.selected;
    
    _localVideoSource.useBackCamera = sender.selected;
}

-(void)speakerBtnAction:(UIButton*)sender{
    if (sender) {
        sender.selected = !sender.selected;
        if (sender.selected) {
            //关闭扬声器
            [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
        }else{
            //切换到扬声器模式
            [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
            
        }
    }else{
        //切换到扬声器模式
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    }
    
}

#pragma mark -- getter
-(void)buildClose{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(20, KScreenHeight - 60, (KScreenWidth-60)/3, 40);
    btn.backgroundColor = [UIColor blackColor];
    [btn setTitle:@"关闭" forState:0];
    [btn addTarget:self action:@selector(closeAction) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
    
    UIButton *speakerBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    speakerBtn.frame = CGRectMake(CGRectGetMaxX(btn.frame)+10, KScreenHeight - 60, (KScreenWidth-60)/3, 40);
    speakerBtn.backgroundColor = [UIColor blackColor];
    speakerBtn.titleLabel.font = btn.titleLabel.font;
    [speakerBtn setTitleColor:btn.currentTitleColor forState:UIControlStateNormal];
    [speakerBtn setTitle:@"关闭扬声器" forState:UIControlStateNormal];
    [speakerBtn setTitle:@"开启扬声器" forState:UIControlStateSelected];
    [speakerBtn addTarget:self action:@selector(speakerBtnAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:speakerBtn];
    
    self.swichCameraBtn.frame = CGRectMake(CGRectGetMaxX(speakerBtn.frame)+10, KScreenHeight - 60, (KScreenWidth-60)/3, 40);
    self.swichCameraBtn.titleLabel.font = btn.titleLabel.font;
    [self.swichCameraBtn setTitleColor:btn.currentTitleColor forState:UIControlStateNormal];
    [self.view addSubview:self.swichCameraBtn];
}


-(UILabel*)statusLabel{
    if (!_statusLabel) {
        _statusLabel = [[UILabel alloc] init];
        _statusLabel.frame = CGRectMake(0, 20, KScreenWidth, 40);
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.textColor = [UIColor purpleColor];
        [self.view addSubview:_statusLabel];
        
    }
    return _statusLabel;
}

-(RTCEAGLVideoView*)remoteVideoView{
    if (!_remoteVideoView) {
        RTCEAGLVideoView *remoteVideoView = [[RTCEAGLVideoView alloc] initWithFrame:CGRectMake(375/2.0, 375/2.0*1.3 + 60, 375/2.0, 375/2.0*1.3)];
        _remoteVideoView = remoteVideoView;
    }
    return _remoteVideoView;
    
}

-(UIButton*)swichCameraBtn{
    if (!_swichCameraBtn) {
        _swichCameraBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        _swichCameraBtn.backgroundColor = [UIColor blackColor];
        [_swichCameraBtn setTitle:@"前置摄像头" forState:UIControlStateNormal];
        [_swichCameraBtn setTitle:@"后置摄像头" forState:UIControlStateSelected];
        [_swichCameraBtn addTarget:self action:@selector(swichCameraAction:) forControlEvents:UIControlEventTouchUpInside];
        
    }
    return _swichCameraBtn;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
