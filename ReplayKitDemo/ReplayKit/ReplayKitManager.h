//
//  ReplayKitManager.h
//  ReplayKitDemo
//
//  Created by ydd on 2019/5/24.
//  Copyright © 2019 ydd. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef enum : NSUInteger {
    /** 正常 */
    ReplayKitErrorCode_normal = 0,
    /** 重复开启录制 */
    ReplayKitErrorCode_100 = 100,
    /** ReplayKit 不可用 */
    ReplayKitErrorCode_101,
    /** ReplayKit启动录制出错 */
    ReplayKitErrorCode_102,
    /** 停止录制出错 */
    ReplayKitErrorCode_103,
    /** 用户拒绝视频存入相册 */
    ReplayKitErrorCode_104,
    /**视频存入相册失败 */
    ReplayKitErrorCode_105,
    /**视频存入相册成功 */
    ReplayKitErrorCode_106,
    
} ReplayKitErrorCode;

@interface ReplayKitManager : NSObject

@property (nonatomic, copy) void (^RecordErrorHandle)(ReplayKitErrorCode code,  NSError * _Nullable error);
/** 是否录制扬声器音频 ,默认NO, iOS11以后有效 */
@property (nonatomic, assign) BOOL recordAudioMic;
/** 不录制音频, 默认 NO */
@property (nonatomic, assign) BOOL unableAudio;
/** 存入相册, 默认 YES */
@property (nonatomic, assign) BOOL savePhotos;


+ (ReplayKitManager *)shareManager;

- (void)startReplayKitRecord;


- (void)stopReplayKitRecordCompletion:(void(^)(NSString *videoPath))completion;


@end

NS_ASSUME_NONNULL_END
