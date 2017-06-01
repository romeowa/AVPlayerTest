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


@interface ViewController () <AVAssetResourceLoaderDelegate, NSURLConnectionDataDelegate>
@property (strong, nonatomic) AVPlayer *player;
@property (strong, nonatomic) AVPlayerItem *currentPlayerItem;

@property (strong, nonatomic) NSURLConnection *connection;
@property (strong, nonatomic) NSMutableArray *pendingRequests;
@property (strong, nonatomic) NSMutableData *songData;
@property (strong, nonatomic) NSHTTPURLResponse *response;


@end

@implementation ViewController {
    NSURL *_originalURL;
}

- (IBAction)click:(id)sender {
//http://cdn.mos.musicradar.com/audio/samples/abstract-demo-loops/LFC130-02.mp3
//https://allthingsaudio.wikispaces.com/file/view/Shuffle%20for%20K.M.mp3/139190697/Shuffle%20for%20K.M.mp3
//http://www.nimh.nih.gov/audio/neurogenesis.mp3

    _originalURL = [NSURL URLWithString:@"https://allthingsaudio.wikispaces.com/file/view/Shuffle%20for%20K.M.mp3/139190697/Shuffle%20for%20K.M.mp3"];
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
    [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1.f, 1.f) queue:nil usingBlock:^(CMTime time) {
        CMTime duration = [weakSelf.currentPlayerItem duration];
        NSLog(@"%@",[NSNumber numberWithDouble:CMTimeGetSeconds(duration)]);
    }];
    
    NSError *error;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    
    [self.player play];
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
//                [self.player play];
                break;
            default:
                break;
        }
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    
}
#pragma mark - AVAssetResourceLoaderDelegate
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSLog(@"shouldWaitForLoadingOfRequestedResource!!!");
    if (self.connection == nil) {
        NSURL *interceptedURL = [loadingRequest.request URL];
        NSURLComponents *actualURLComponents = [[NSURLComponents alloc] initWithURL:interceptedURL resolvingAgainstBaseURL:NO];
        
        if(interceptedURL == nil ||
           actualURLComponents == nil) {
            [loadingRequest finishLoading];
            return NO;
        }

        
        actualURLComponents.scheme = [[NSURLComponents alloc] initWithURL:_originalURL resolvingAgainstBaseURL:NO].scheme;
        
        NSURLRequest *request = [NSURLRequest requestWithURL:[actualURLComponents URL]];
        
        self.connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
        [self.connection setDelegateQueue:[NSOperationQueue mainQueue]];
        
        [self.connection start];
    }
    
    [self.pendingRequests addObject:loadingRequest];
    
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    [self.pendingRequests removeObject:loadingRequest];
}

#pragma mark - NSURLConnectionDataDelegate
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    NSLog(@"didReceiveResponse >>>");
    self.songData = [NSMutableData data];
    self.response = (NSHTTPURLResponse *)response;
    
    [self processPendingRequests];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    NSLog(@"didReceiveData data = %lu, total = %lu",[data length],(unsigned long)[self.songData length]);
    
    [self.songData appendData:data];
    [self processPendingRequests];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    NSLog(@"!!!!!!!!!!! finish");
    [self processPendingRequests];
    NSString *cachedFilePath = [NSTemporaryDirectory() stringByAppendingString:@"cached.mp3"];
    [self.songData writeToFile:cachedFilePath atomically:YES];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    
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
    
    NSString *mimeType = [self.response MIMEType];
//    CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(mimeType), NULL);
    
    contentInformationRequest.byteRangeAccessSupported = YES;
    contentInformationRequest.contentType = @"mp3";
    contentInformationRequest.contentLength = 5216573;
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


@end
