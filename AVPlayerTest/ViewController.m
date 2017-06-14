//
//  ViewController.m
//  AVPlayerTest
//
//  Created by howard.han on 2017. 5. 29..
//  Copyright © 2017년 howard.han. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <MobileCoreServices/UTType.h>

static void *itemContext = &itemContext;
static void *playerContext = &playerContext;

@interface ViewController () <AVAssetResourceLoaderDelegate, NSURLSessionDataDelegate>
@property (strong, nonatomic) AVPlayer *player;
@property (strong, nonatomic) AVPlayerItem *currentPlayerItem;

@property (strong, nonatomic) NSMutableArray *pendingRequests;
@property (strong, nonatomic) NSMutableData *songData;
@property (strong, nonatomic) NSHTTPURLResponse *response;

@property (strong, nonatomic) NSURLSession *session;


@end

@implementation ViewController {
    NSURL *_originalURL;
}


#pragma mark - event handlers
- (void)viewDidLoad {
    [super viewDidLoad];
    
    //http://cdn.mos.musicradar.com/audio/samples/abstract-demo-loops/LFC130-02.mp3
    //http://www.nimh.nih.gov/audio/neurogenesis.mp3
    //http://www.goclassic.co.kr/mp3/Beethoven_Appasionata_II_&_III.mp3 //교향곡
    _originalURL = [NSURL URLWithString:@"http://www.nimh.nih.gov/audio/neurogenesis.mp3"];
    AVURLAsset *urlAsset = [AVURLAsset assetWithURL:[self URL:_originalURL withCutsomscheme:@"howard"]];
    
    [urlAsset.resourceLoader setDelegate:self queue:dispatch_get_main_queue()];
    
    self.pendingRequests = [NSMutableArray new];
    self.currentPlayerItem = [AVPlayerItem playerItemWithAsset:urlAsset];
    [self.currentPlayerItem addObserver:self
                             forKeyPath:@"status"
                                options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                                context:itemContext];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.currentPlayerItem];
    
    self.player = [AVPlayer playerWithPlayerItem:self.currentPlayerItem];
    
    __weak __typeof(&*self)weakSelf = self;
    [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5f, NSEC_PER_SEC)
                                              queue:NULL
                                         usingBlock:^(CMTime time) {
                                             if (CMTIME_IS_VALID(self.currentPlayerItem.duration) == NO ||
                                                 CMTIME_IS_VALID(time) == NO) {
                                                 return;
                                             }
                                             
                                             float total = CMTimeGetSeconds(weakSelf.currentPlayerItem.duration);
                                             float current = CMTimeGetSeconds(time);
                                             
                                             weakSelf.uiSlider.value =  current/total;
                                             NSLog(@"time = %f, duration = %f",current,total);
                                         }];
    
    NSError *error;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    
    self.songData = [NSMutableData data];
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context == itemContext) {
        AVPlayerItemStatus status = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
        switch (status) {
            case AVPlayerItemStatusUnknown:
                NSLog(@"AVPlayerItemStatusUnknown");
                break;
            case AVPlayerItemStatusFailed:
                NSLog(@"AVPlayerItemStatusFailed");
                break;
            case AVPlayerItemStatusReadyToPlay:
                NSLog(@"AVPlayerItemStatusReadyToPlay");
                [self.player play];
                break;
            default:
                break;
        }
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    
}

- (IBAction)valuenChangeEnd:(id)sender {
    UISlider *slider = (UISlider *)sender;
    if (slider == nil) {
        return;
    }
    
    if (self.currentPlayerItem == nil ||
        self.player.status != AVPlayerStatusReadyToPlay ||
        CMTIME_IS_INVALID(self.currentPlayerItem.duration) == YES ) {
        return;
    }
    
    double timeToPlay = CMTimeGetSeconds(self.currentPlayerItem.duration);
    [self.player.currentItem seekToTime:CMTimeMakeWithSeconds(timeToPlay *  slider.value,NSEC_PER_SEC)
                      completionHandler:^(BOOL finished) {
                          if (finished == NO)
                              return;
                      }];
}

- (IBAction)clearCacheButtonClicked:(id)sender {
    [self clearCache];
}


#pragma mark - AVAssetResourceLoaderDelegate
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSLog(@"request = %@",loadingRequest);
    
    if (self.session== nil) {
        NSLog(@"create new session");
        self.songData = [NSMutableData data];
    } else {
        NSLog(@"session invalidate!");
        [self.session invalidateAndCancel];
    }
    
    NSURL *interceptedURL = [loadingRequest.request URL];
    NSURLComponents *actualURLComponents = [[NSURLComponents alloc] initWithURL:interceptedURL resolvingAgainstBaseURL:NO];
    
    if(interceptedURL == nil ||
       actualURLComponents == nil) {
        [loadingRequest finishLoading];
        return NO;
    }
    
    
    actualURLComponents.scheme = [[NSURLComponents alloc] initWithURL:_originalURL resolvingAgainstBaseURL:NO].scheme;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[actualURLComponents URL]];
    
    if(loadingRequest.dataRequest.requestedOffset != 0) {
        [request setValue:[NSString stringWithFormat:@"bytes=%llu-", loadingRequest.dataRequest.requestedOffset] forHTTPHeaderField:@"Range"];
    }
    
    
    
    self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                 delegate:self
                                            delegateQueue:[NSOperationQueue mainQueue]];
    
    [[self.session dataTaskWithRequest:request] resume];
    [self.pendingRequests addObject:loadingRequest];
    
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSLog(@"cancel request");
    [loadingRequest finishLoading];
    [self.pendingRequests removeObject:loadingRequest];
}


#pragma mark - NSURLSessionDataDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    completionHandler(NSURLSessionResponseAllow);
    NSLog(@"didReceiveResponse >>> %@",response);
    
    self.response = (NSHTTPURLResponse *)response;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
        NSLog(@"didReceiveData data = %lu, total = %lu",(unsigned long)[data length],(unsigned long)[self.songData length]);
    [self.songData appendData:data];
    float width = ((float)(self.songData.length + data.length) / (float)self.response.expectedContentLength) * self.view.frame.size.width;
    [self.progressVIew setFrame:CGRectMake(0, 100, width, 10)];
    
    [self processPendingRequests];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask {
    NSLog(@"000000000000");
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse * _Nullable cachedResponse))completionHandler {
    NSLog(@"1111111111");
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {
    if(error == nil) {
        NSLog(@"completed!!!");
        
        [self processPendingRequests];
        
        [self clearCache];
        NSString *cachedFilePath = [NSTemporaryDirectory() stringByAppendingString:@"test.mp3"];
        [self.songData writeToFile:cachedFilePath atomically:YES];
        
//        NSString *exportedFilePath = [NSTemporaryDirectory() stringByAppendingString:@"exported.m4a"];
//        
//        if ([[NSFileManager defaultManager] fileExistsAtPath:exportedFilePath] == YES) {
//            [[NSFileManager defaultManager] removeItemAtPath:exportedFilePath error:nil];
//        }
//        
//        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:self.player.currentItem.asset presetName:AVAssetExportPresetHighestQuality];
//        NSArray<NSString *> *supportedFileTypes = [exportSession supportedFileTypes];
//        exportSession.metadata = self.player.currentItem.asset.metadata;
//        exportSession.outputFileType = supportedFileTypes[0];
//        exportSession.outputURL = [NSURL fileURLWithPath:exportedFilePath];
//        [exportSession exportAsynchronouslyWithCompletionHandler:^{
//            switch(exportSession.status){
//                case AVAssetExportSessionStatusExporting:
//                    NSLog(@"Exporting...");
//                    break;
//                case AVAssetExportSessionStatusCompleted:
//                    NSLog(@"Export completed, wohooo!!");
//                    break;
//                case AVAssetExportSessionStatusWaiting:
//                    NSLog(@"Waiting...");
//                    break;
//                case AVAssetExportSessionStatusFailed:
//                    NSLog(@"Failed with error: %@", exportSession.error);
//                    break;
//                case AVAssetExportSessionStatusUnknown:
//                    NSLog(@"UnKnown...");
//                    break;
//                case AVAssetExportSessionStatusCancelled:
//                    NSLog(@"Cancelled...");
//                    break;
//            }
//        }];
    }
}



#pragma mark - private methods
- (NSURL *)URL:(NSURL *)URL withCutsomscheme:(NSString *)scheme {
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:URL resolvingAgainstBaseURL:NO];
    components.scheme = scheme;
    return [components URL];
}

- (void)processPendingRequests {
    NSMutableArray *requestsCompleted = [NSMutableArray array];
    
    for (AVAssetResourceLoadingRequest *loadingRequest in self.pendingRequests) {
        [self fillInContentInformation:loadingRequest.contentInformationRequest];
        
        BOOL didRespondCompletely = [self respondWithDataForRequest:loadingRequest.dataRequest];
        
        if (didRespondCompletely == YES) {
            [requestsCompleted addObject:loadingRequest];
            [loadingRequest finishLoading];
        }
    }
    
    [self.pendingRequests removeObjectsInArray:requestsCompleted];
}


- (void)fillInContentInformation:(AVAssetResourceLoadingContentInformationRequest *)contentInformationRequest {
    if (contentInformationRequest == nil || self.response == nil) {
        return;
    }
    
    //    NSString *mimeType = [self.response MIMEType];
    //    CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(mimeType), NULL);
    contentInformationRequest.byteRangeAccessSupported = YES;
    //제대로 contentType 받도록 수정.
    contentInformationRequest.contentType = @"mp3";
    contentInformationRequest.contentLength = self.response.expectedContentLength;
    
    NSLog(@"contentLength = %lld, ContentType = %@",contentInformationRequest.contentLength, contentInformationRequest.contentType);
}

- (BOOL)respondWithDataForRequest:(AVAssetResourceLoadingDataRequest *)dataRequest {
    long long startOffset = dataRequest.requestedOffset;
    if (dataRequest.currentOffset != 0) {
        startOffset = dataRequest.currentOffset;
    }
    
    if (self.songData.length < startOffset) {
        return NO;
    }
    
    NSUInteger unreadBytes = self.songData.length - (NSUInteger)startOffset;
    
    NSUInteger numberOfBytesToRespondWith = MIN((NSUInteger)dataRequest.requestedLength, unreadBytes);
    
    [dataRequest respondWithData:[self.songData subdataWithRange:NSMakeRange((NSUInteger)startOffset, numberOfBytesToRespondWith)]];
    
    long long endOffset = startOffset + dataRequest.requestedLength;
    BOOL didRespondFully = self.songData.length >= endOffset;
    
    return didRespondFully;
}

- (void)clearCache {
    NSString *cachedFilePath = [NSTemporaryDirectory() stringByAppendingString:@"test.mp3"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:cachedFilePath] == YES) {
        [[NSFileManager defaultManager] removeItemAtPath:cachedFilePath error:nil];
    }
}

@end
