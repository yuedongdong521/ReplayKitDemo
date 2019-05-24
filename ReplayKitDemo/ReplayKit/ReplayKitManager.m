//
//  ReplayKitManager.m
//  ReplayKitDemo
//
//  Created by ydd on 2019/5/24.
//  Copyright © 2019 ydd. All rights reserved.
//

#import "ReplayKitManager.h"
#import <ReplayKit/ReplayKit.h>
#import <AssetsLibrary/ALAssetsLibrary.h>
#import "PhotoSaveLibraryManager.h"

static ReplayKitManager *_manager;

@interface ReplayKitManager ()<RPScreenRecorderDelegate>
{
    dispatch_queue_t _captureReplayQueue;
}

@property (nonatomic, strong) RPScreenRecorder *recorder;
@property (nonatomic, strong) AVAssetWriter *videoWriter;
@property (nonatomic, strong) AVAssetWriterInput *videoWriterInput;
@property (nonatomic, strong) AVAssetWriterInput *audioWriterInput;
@property (nonatomic, assign) BOOL startRecord;
@property (nonatomic, copy) NSString *videoTempPath;
@property (nonatomic, copy) void(^recordCompletion)(NSString *videoPath);

@end

@implementation ReplayKitManager

+ (ReplayKitManager *)shareManager
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _manager = [[ReplayKitManager alloc] init];
    });
    return _manager;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _recorder = [RPScreenRecorder sharedRecorder];
        _recorder.delegate = self;
        self.savePhotos = YES;
        _captureReplayQueue = dispatch_queue_create("ReplayKit.VideoWriteQueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)startReplayKitRecord
{
    if (_recorder.isRecording) {
        NSLog(@"ReplayKitManager - 已经开始录制");
        [self replayRecordCode:ReplayKitErrorCode_100 error:nil];
        return;
    }
    if (!_recorder.isAvailable) {
        NSLog(@"ReplayKitManager - 不可用");
        [self replayRecordCode:ReplayKitErrorCode_101 error:nil];
    }
    
    if (@available(iOS 11.0, *)) {
        [self startRecordOnIOS11OrLater];
    } else if (@available(iOS 10.0, *)) {
        [self startRecordOnIOS10];
    } else if (@available(iOS 9.0, *)) {
        [self startRecordOnIOS9];
    }
}

- (void)stopReplayKitRecordCompletion:(void(^)(NSString *videoPath))completion
{
    self.recordCompletion = completion;
    __weak typeof(self) weakself = self;
    if (@available(iOS 11.0, *)) {
        [_recorder stopCaptureWithHandler:^(NSError * _Nullable error) {
            __strong typeof(self) strongself = weakself;
            [strongself stopVideoWriter];
            if (error) {
                [self replayRecordCode:ReplayKitErrorCode_103 error:error];
            }
        }];
    } else {
        [_recorder stopRecordingWithHandler:^(RPPreviewViewController * _Nullable previewViewController, NSError * _Nullable error) {
            __strong typeof(self) strongself = weakself;
            if (!error || error.code == 0) {
                 NSURL *movieURL =  [[previewViewController valueForKey:@"movieURL"] copy];
                [strongself writerLibraryWithVideoPath:movieURL.path];
            } else {
                [self replayRecordCode:ReplayKitErrorCode_103 error:error];
            }
        }];
    }
}

- (void)cancelReplayKitRecord
{
    if (!_recorder.recording) {
        return;
    }
    __weak typeof(self) weakself = self;
    if (@available(iOS 11.0, *)) {
        [_recorder stopCaptureWithHandler:^(NSError * _Nullable error) {
            [weakself deleteRecordVideo];
        }];
    } else {
        [_recorder stopRecordingWithHandler:^(RPPreviewViewController * _Nullable previewViewController, NSError * _Nullable error) {
            [weakself deleteRecordVideo];
        }];
    }
}

- (void)startRecordOnIOS9
{
    __weak typeof(self) weakself = self;
    [_recorder startRecordingWithMicrophoneEnabled:!self.unableAudio handler:^(NSError *error){
        __strong typeof(self) strongself = weakself;
        [strongself beginRecordHander:error];
    }];
}

- (void)startRecordOnIOS10 {
    _recorder.microphoneEnabled =!self.unableAudio;
    __weak typeof(self) weakself = self;
    if (@available(iOS 10.0, *)) {
        [_recorder startRecordingWithHandler:^(NSError * _Nullable error) {
            __strong typeof(self) strongself = weakself;
            [strongself beginRecordHander:error];
        }];
    } else {
        // Fallback on earlier versions
    }
}

- (void)startRecordOnIOS11OrLater
{
    [self setupVideoWriterConfig];
    _recorder.microphoneEnabled = !self.unableAudio;
    
    if (@available(iOS 11.0, *)) {
        __weak typeof(self) weakself = self;
        [_recorder startCaptureWithHandler:^(CMSampleBufferRef  _Nonnull sampleBuffer, RPSampleBufferType bufferType, NSError * _Nullable error) {
            __strong typeof(self) strongself = weakself;
            if (error) {
                return;
            }
            [strongself writeVideoBuffer:sampleBuffer bufferType:bufferType];
        } completionHandler:^(NSError * _Nullable error) {
            NSLog(@"屏幕录制 recorder completionHandler error : %@", error);
            __strong typeof(self) strongself = weakself;
            [strongself beginRecordHander:error];
        }];
    } else {
        // Fallback on earlier versions
    }
}

- (void)beginRecordHander:(NSError *)error
{
    if (error) {
        NSLog(@"ReplayKitManager - 启动录制失败 error : %@", error);
        [self replayRecordCode:ReplayKitErrorCode_102 error:error];
    } else {
        [self replayRecordCode:ReplayKitErrorCode_normal error:error];
    }
}

- (void)replayRecordCode:(ReplayKitErrorCode)code error:(NSError *)error
{
    if (_RecordErrorHandle) {
        _RecordErrorHandle(code, error);
    }
}

- (void)stopVideoWriter {
    __weak typeof(self) weakself = self;
    if (self.videoWriter && self.videoWriter.status == AVAssetWriterStatusWriting) {
        dispatch_async(_captureReplayQueue, ^{
            [self.videoWriterInput markAsFinished];
            [self.audioWriterInput markAsFinished];
            [self.videoWriter finishWritingWithCompletionHandler:^{
                 __strong typeof(self) strongself = weakself;
                [strongself writerLibraryWithVideoPath:strongself.videoTempPath];
            }];
        });
    }
}

- (void)writerLibraryWithVideoPath:(NSString *)videoPath
{
    if (self.recordCompletion) {
        self.recordCompletion(videoPath);
    }
    if (!self.savePhotos) {
        return;
    }
    // 保存视频进相册
    __weak typeof(self) weakself = self;
    [PhotoSaveLibraryManager requestPhotoAuthorizationBlock:^(BOOL hasAuthorize) {
        __strong typeof(self) strongself = weakself;
        if (hasAuthorize) {
            UISaveVideoAtPathToSavedPhotosAlbum(videoPath, strongself, @selector(video:didFinishSavingWithError:contextInfo:), NULL);
        } else {
            [self replayRecordCode:ReplayKitErrorCode_104 error:nil];
        }
    }];
}

- (void)video:(NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    NSLog(@"屏幕录制保存 error : %@", error);
    if (!error || error.code == 0) {
        [self replayRecordCode:ReplayKitErrorCode_106 error:error];
    } else {
        [self replayRecordCode:ReplayKitErrorCode_105 error:error];
    }
    // 删除录制的视频
    [self deleteRecordVideo];
}

- (void)deleteRecordVideo
{
    if (_recorder.recording) {
        return;
    }
    [_recorder discardRecordingWithHandler:^{
    }];
    if (@available(iOS 11.0, *)) {
        [self resetVideoWriterConfig];
    }
}
- (void)writeVideoBuffer:(CMSampleBufferRef)sampleBuffer bufferType:(RPSampleBufferType)bufferType
API_AVAILABLE(ios(10.0)){
    @autoreleasepool {
        CFRetain(sampleBuffer);
        dispatch_async(_captureReplayQueue, ^{
            @synchronized(self) {
                if (!CMSampleBufferDataIsReady(sampleBuffer)) {
                    CFRelease(sampleBuffer);
                    return;
                }
                if (self.videoWriter.status == AVAssetWriterStatusUnknown && !self.startRecord) {
                    [self.videoWriter startWriting];
                    [self.videoWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
                    self.startRecord = YES;
                    NSLog(@"屏幕录制开启session 视频处");
                }
                
                if (self.videoWriter.status == AVAssetWriterStatusFailed) {
                    NSLog(@"屏幕录制AVAssetWriterStatusFailed");
                    CFRelease(sampleBuffer);
                    return;
                }
                if (bufferType == RPSampleBufferTypeVideo) {
                    if ([self.videoWriterInput isReadyForMoreMediaData] && self.startRecord) {
                        @try {
                            [self.videoWriterInput appendSampleBuffer:sampleBuffer];
                            NSLog(@"屏幕录制写入视频数据");
                        } @catch (NSException *exception) {
                            NSLog(@"屏幕录制写入视频数据失败");
                        }
                    }
                }
                
                BOOL recordAudio = self.recordAudioMic ? bufferType == RPSampleBufferTypeAudioMic : bufferType == RPSampleBufferTypeAudioApp;
                if (recordAudio) {
                    if ([self.audioWriterInput isReadyForMoreMediaData] && self.startRecord) {
                        @try {
                            [self.audioWriterInput appendSampleBuffer:sampleBuffer];
                            NSLog(@"屏幕录制写入音频数据");
                        } @catch (NSException *exception) {
                            NSLog(@"屏幕录制写入音频数据失败");
                        }
                    }
                }
                CFRelease(sampleBuffer);
            }
        });
    }
}


#pragma mark RPScreenRecorderDelegate
- (void)screenRecorderDidChangeAvailability:(RPScreenRecorder *)screenRecorder
{
    NSLog(@"ReplayKitManager - accessibilityValue : %@", screenRecorder.accessibilityValue);
}

- (void)screenRecorder:(RPScreenRecorder *)screenRecorder didStopRecordingWithPreviewViewController:(RPPreviewViewController *)previewViewController error:(NSError *)error
{
    NSLog(@"ReplayKitManager - stopRecording - error : %@", error);
    [self replayRecordCode:ReplayKitErrorCode_103 error:error];
}

- (void)screenRecorder:(RPScreenRecorder *)screenRecorder didStopRecordingWithError:(NSError *)error previewViewController:(RPPreviewViewController *)previewViewController
{
    NSLog(@"ReplayKitManager - stopRecording - error : %@", error);
     [self replayRecordCode:ReplayKitErrorCode_103 error:error];
}


- (void)setupVideoWriterConfig
{
    if ([self.videoWriter canAddInput:self.videoWriterInput]) {
        [self.videoWriter addInput:self.videoWriterInput];
    } else {
        NSLog(@"ReplayKitManager - 无法添加Video Writer Input");
    }
    
    if ([self.videoWriter canAddInput:self.audioWriterInput]) {
        [self.videoWriter addInput:self.audioWriterInput];
    } else {
        NSLog(@"ReplayKitManager - 无法添加Video Writer Input");
    }
    self.startRecord = NO;
}

- (void)resetVideoWriterConfig
{
    _videoWriter = nil;
    _videoWriterInput = nil;
    _audioWriterInput = nil;
}

- (AVAssetWriter *)videoWriter
{
    if (!_videoWriter) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:self.videoTempPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:self.videoTempPath error:nil];
        }
        NSURL *outputURL = [NSURL fileURLWithPath:self.videoTempPath];
        NSError *error = nil;
        _videoWriter = [AVAssetWriter assetWriterWithURL:outputURL fileType:AVFileTypeMPEG4 error:&error];
        if (error) {
            NSLog(@"ReplayKitManager - 创建Video Writer失败：%@", [error localizedDescription]);
        }
    }
    return _videoWriter;
}

- (AVAssetWriterInput *)videoWriterInput
{
    if (!_videoWriterInput) {
        CGSize size = [UIScreen mainScreen].bounds.size;
        size = CGSizeMake(size.width * 2,size.height * 2);
        NSDictionary *compressionProperties = @{ AVVideoAverageBitRateKey : @(1280 * 1024),
                                                 AVVideoMaxKeyFrameIntervalKey : @(1)
                                                 };
        NSDictionary *videoSettings = @{AVVideoCodecKey : AVVideoCodecH264,
                                        AVVideoWidthKey : @(size.width),
                                        AVVideoHeightKey : @(size.height),
                                        AVVideoCompressionPropertiesKey : compressionProperties};
        _videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                               outputSettings:videoSettings];
        _videoWriterInput.expectsMediaDataInRealTime = YES;
       
    }
    return _videoWriterInput;
}

- (AVAssetWriterInput *)audioWriterInput
{
    if (!_audioWriterInput) {
        AudioChannelLayout acl;
        bzero(&acl, sizeof(acl));
        acl.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_5_1_D;
        NSDictionary *audioSettingDic = @{
                                          AVSampleRateKey : @(44100),
                                          AVFormatIDKey : @(kAudioFormatMPEG4AAC_HE),
                                          AVNumberOfChannelsKey : @(6),
                                          AVChannelLayoutKey : [NSData dataWithBytes:&acl length:sizeof(acl)],
                                          };
        //
        //        audioSettingDic = @{
        //                            AVEncoderBitRatePerChannelKey : @(28000),
        //                            AVFormatIDKey : @(kAudioFormatMPEG4AAC),
        //                            AVNumberOfChannelsKey : @(1),
        //                            AVSampleRateKey : @(22050)
        //                            };
        
        _audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                               outputSettings:audioSettingDic];
        _audioWriterInput.expectsMediaDataInRealTime = YES;
    }
    return _audioWriterInput;
}

- (NSString *)videoTempPath
{
    if (!_videoTempPath) {
        _videoTempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"replayKitVideo.mp4"];
        
    }
    return _videoTempPath;
}



@end
