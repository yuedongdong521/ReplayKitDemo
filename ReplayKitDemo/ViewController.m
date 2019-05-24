//
//  ViewController.m
//  ReplayKitDemo
//
//  Created by ydd on 2019/5/24.
//  Copyright © 2019 ydd. All rights reserved.
//

#import "ViewController.h"
#import "ReplayKitManager.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UILabel *timeLabel;

@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, assign) int videoTime;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    __weak typeof(self) weakself = self;
    [ReplayKitManager shareManager].RecordErrorHandle = ^(ReplayKitErrorCode code, NSError * _Nullable error) {
        NSLog(@"ReplayKitErrorCode : %lu", (unsigned long)code);
    };

    
    
}

- (void)setupRecordTimer
{
    if (!_timer) {
        [[ReplayKitManager shareManager] startReplayKitRecord];
        _videoTime = 0;
        _timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(timerAction) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    } else {
        [[ReplayKitManager shareManager] stopReplayKitRecordCompletion:^(NSString * _Nonnull videoPath) {
            
        }];
        
        if ([_timer isValid]) {
            [_timer invalidate];
        }
        _timer = nil;
        _timeLabel.text = @"";
    }
}

- (void)timerAction
{
    self.timeLabel.text = [NSString stringWithFormat:@"录制中:%2d:%2d", self.videoTime / 60, self.videoTime % 60];
    self.videoTime++;
}
- (IBAction)recordAction:(id)sender {
    ((UIButton *) sender).selected = !((UIButton *) sender).selected;
    [self setupRecordTimer];
    
}

@end
