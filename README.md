# [AppRTCChat](https://github.com/zhuzhuxingtianxia/AppRTCChat)

**webRTC**之libjingle_peerconnection

## 如何测试

- 运行WebSocket服务端前，你需要用Node.js的NPM去安装依赖包
- 命令行中执行: node -v 查看node是否安装，若没有安装则先安装Homebrew,Mac系统的包管理器
- 终端安装：/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
- 安装node.js终端：brew install node
- 用命令行CD到server.js所在目录下即SkyRTC-demo-master文件夹
- 命令行中执行:node server.js

然后就可以运行项目了

- 设置服务器ip地址和端口号
- 设置房间号，然后就可以进入了！

## 存在的问题
```
1.远端视频模糊
2.扬声器有回音
3.STUN和TURN服务器不稳定或不可用回导致远程视频黑屏。（一直没学会STUN和TURN服务器搭建，很郁闷）
```
## 效果图
![img](https://github.com/zhuzhuxingtianxia/AppRTCChat/blob/master/video.png)

## 学习参考地址
1. [http://www.jianshu.com/p/c49da1d93df4](http://www.jianshu.com/p/c49da1d93df4)
2. [https://github.com/ISBX/apprtc-ios](https://github.com/ISBX/apprtc-ios)
3. [https://github.com/crossle/AppRTCMobile](https://github.com/crossle/AppRTCMobile)
