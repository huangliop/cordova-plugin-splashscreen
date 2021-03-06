/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "CDVSplashScreen.h"
#import <Cordova/CDVViewController.h>
#import <Cordova/CDVScreenOrientationDelegate.h>
#import "CDVViewController+SplashScreen.h"

#define kSplashScreenDurationDefault 3000.0f



UIButton* _skipBtn;
UILabel* _countdown;
int secondsLeft;
NSTimer* _timer;

@implementation CDVSplashScreen

- (void)pluginInitialize
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pageDidLoad) name:CDVPageDidLoadNotification object:nil];

    [self setVisible:YES];
}

- (void)show:(CDVInvokedUrlCommand*)command
{
    [self setVisible:YES];
}

- (void)hide:(CDVInvokedUrlCommand*)command
{
    [self setVisible:NO];
}

- (void)pageDidLoad
{
    id autoHideSplashScreenValue = [self.commandDelegate.settings objectForKey:[@"AutoHideSplashScreen" lowercaseString]];

    // if value is missing, default to yes
    if ((autoHideSplashScreenValue == nil) || [autoHideSplashScreenValue boolValue]) {
        [self setVisible:NO];
    }
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
    [self updateImage];
}

- (void)createViews
{
    /*
     * The Activity View is the top spinning throbber in the status/battery bar. We init it with the default Grey Style.
     *
     *     whiteLarge = UIActivityIndicatorViewStyleWhiteLarge
     *     white      = UIActivityIndicatorViewStyleWhite
     *     gray       = UIActivityIndicatorViewStyleGray
     *
     */

    // Determine whether rotation should be enabled for this device
    // Per iOS HIG, landscape is only supported on iPad and iPhone 6+
    CDV_iOSDevice device = [self getCurrentDevice];
    BOOL autorotateValue = (device.iPad || device.iPhone6Plus) ?
        [(CDVViewController *)self.viewController shouldAutorotateDefaultValue] :
        NO;
    
    [(CDVViewController *)self.viewController setEnabledAutorotation:autorotateValue];

    NSString* topActivityIndicator = [self.commandDelegate.settings objectForKey:[@"TopActivityIndicator" lowercaseString]];
    UIActivityIndicatorViewStyle topActivityIndicatorStyle = UIActivityIndicatorViewStyleGray;

    if ([topActivityIndicator isEqualToString:@"whiteLarge"])
    {
        topActivityIndicatorStyle = UIActivityIndicatorViewStyleWhiteLarge;
    }
    else if ([topActivityIndicator isEqualToString:@"white"])
    {
        topActivityIndicatorStyle = UIActivityIndicatorViewStyleWhite;
    }
    else if ([topActivityIndicator isEqualToString:@"gray"])
    {
        topActivityIndicatorStyle = UIActivityIndicatorViewStyleGray;
    }

    UIView* parentView = self.viewController.view;
    parentView.userInteractionEnabled = NO;  // disable user interaction while splashscreen is shown
    _activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:topActivityIndicatorStyle];
    _activityView.center = CGPointMake(parentView.bounds.size.width / 2, parentView.bounds.size.height / 2);
    _activityView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin
        | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin;
    [_activityView startAnimating];

    // Set the frame & image later.
    _imageView = [[UIImageView alloc] init];
    [parentView addSubview:_imageView];

    id showSplashScreenSpinnerValue = [self.commandDelegate.settings objectForKey:[@"ShowSplashScreenSpinner" lowercaseString]];
    // backwards compatibility - if key is missing, default to true
    if ((showSplashScreenSpinnerValue == nil) || [showSplashScreenSpinnerValue boolValue])
    {
        [parentView addSubview:_activityView];
    }
    // Set skip button
    CGRect frame = CGRectMake([UIScreen mainScreen].bounds.size.width-70,20 , 60, 40);
    _skipBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _skipBtn.frame = frame;
    [_skipBtn setTitle:@"跳过" forState: UIControlStateNormal];
    [_skipBtn.layer setBackgroundColor:[UIColor colorWithWhite:0.0 alpha:0.0].CGColor];
    [_skipBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    
    [_skipBtn addTarget:self action:@selector(hideViews) forControlEvents:UIControlEventTouchUpInside];
    [_skipBtn setAlpha:0];
    [parentView setUserInteractionEnabled:YES];
    [parentView addSubview:_skipBtn];
    
    
    //Set countdown Lable
    CGRect countdownFrame=CGRectMake(10,20, 40, 40);
    _countdown=[[UILabel alloc] initWithFrame:countdownFrame];
    _countdown.textColor=[UIColor whiteColor];
    [_countdown setAlpha:0];
    [parentView addSubview:_countdown];
    
    // Frame is required when launching in portrait mode.
    // Bounds for landscape since it captures the rotation.
    [parentView addObserver:self forKeyPath:@"frame" options:0 context:nil];
    [parentView addObserver:self forKeyPath:@"bounds" options:0 context:nil];
    
    [self updateImage];
}

- (void)hideViews
{
    [_imageView setAlpha:0];
    [_activityView setAlpha:0];
    [_skipBtn setAlpha:0];
    [_countdown setAlpha:0];
}

- (void)destroyViews
{
    [(CDVViewController *)self.viewController setEnabledAutorotation:[(CDVViewController *)self.viewController shouldAutorotateDefaultValue]];

    [_imageView removeFromSuperview];
    [_activityView removeFromSuperview];
    [_skipBtn removeFromSuperview];
    [_countdown removeFromSuperview];
    
    _imageView = nil;
    _activityView = nil;
    _curImageName = nil;
    _skipBtn=nil;
    _countdown=nil;

    self.viewController.view.userInteractionEnabled = YES;  // re-enable user interaction upon completion
    [self.viewController.view removeObserver:self forKeyPath:@"frame"];
    [self.viewController.view removeObserver:self forKeyPath:@"bounds"];
}

- (CDV_iOSDevice) getCurrentDevice
{
    CDV_iOSDevice device;
    
    UIScreen* mainScreen = [UIScreen mainScreen];
    CGFloat mainScreenHeight = mainScreen.bounds.size.height;
    CGFloat mainScreenWidth = mainScreen.bounds.size.width;
    
    int limit = MAX(mainScreenHeight,mainScreenWidth);
    
    device.iPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
    device.iPhone = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone);
    device.retina = ([mainScreen scale] == 2.0);
    device.iPhone4 = (device.iPhone && limit == 480.0);
    device.iPhone5 = (device.iPhone && limit == 568.0);
    // note these below is not a true device detect, for example if you are on an
    // iPhone 6/6+ but the app is scaled it will prob set iPhone5 as true, but
    // this is appropriate for detecting the runtime screen environment
    device.iPhone6 = (device.iPhone && limit == 667.0);
    device.iPhone6Plus = (device.iPhone && limit == 736.0);
    
    return device;
}

- (NSString*)getImageName:(UIInterfaceOrientation)currentOrientation delegate:(id<CDVScreenOrientationDelegate>)orientationDelegate device:(CDV_iOSDevice)device
{
    // Use UILaunchImageFile if specified in plist.  Otherwise, use Default.
    NSString* imageName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UILaunchImageFile"];
    
    NSUInteger supportedOrientations = [orientationDelegate supportedInterfaceOrientations];
    
    // Checks to see if the developer has locked the orientation to use only one of Portrait or Landscape
    BOOL supportsLandscape = (supportedOrientations & UIInterfaceOrientationMaskLandscape);
    BOOL supportsPortrait = (supportedOrientations & UIInterfaceOrientationMaskPortrait || supportedOrientations & UIInterfaceOrientationMaskPortraitUpsideDown);
    // this means there are no mixed orientations in there
    BOOL isOrientationLocked = !(supportsPortrait && supportsLandscape);
    
    if (imageName)
    {
        imageName = [imageName stringByDeletingPathExtension];
    }
    else
    {
        imageName = @"Default";
    }

    // Add Asset Catalog specific prefixes
    if ([imageName isEqualToString:@"LaunchImage"])
    {
        if (device.iPhone4 || device.iPhone5 || device.iPad) {
            imageName = [imageName stringByAppendingString:@"-700"];
        } else if(device.iPhone6) {
            imageName = [imageName stringByAppendingString:@"-800"];
        } else if(device.iPhone6Plus) {
            imageName = [imageName stringByAppendingString:@"-800"];
            if (currentOrientation == UIInterfaceOrientationPortrait || currentOrientation == UIInterfaceOrientationPortraitUpsideDown)
            {
                imageName = [imageName stringByAppendingString:@"-Portrait"];
            }
        }
    }

    if (device.iPhone5)
    { // does not support landscape
        imageName = [imageName stringByAppendingString:@"-568h"];
    }
    else if (device.iPhone6)
    { // does not support landscape
        imageName = [imageName stringByAppendingString:@"-667h"];
    }
    else if (device.iPhone6Plus)
    { // supports landscape
        if (isOrientationLocked)
        {
            imageName = [imageName stringByAppendingString:(supportsLandscape ? @"-Landscape" : @"")];
        }
        else
        {
            switch (currentOrientation)
            {
                case UIInterfaceOrientationLandscapeLeft:
                case UIInterfaceOrientationLandscapeRight:
                        imageName = [imageName stringByAppendingString:@"-Landscape"];
                    break;
                default:
                    break;
            }
        }
        imageName = [imageName stringByAppendingString:@"-736h"];

    }
    else if (device.iPad)
    {   // supports landscape
        if (isOrientationLocked)
        {
            imageName = [imageName stringByAppendingString:(supportsLandscape ? @"-Landscape" : @"-Portrait")];
        }
        else
        {
            switch (currentOrientation)
            {
                case UIInterfaceOrientationLandscapeLeft:
                case UIInterfaceOrientationLandscapeRight:
                    imageName = [imageName stringByAppendingString:@"-Landscape"];
                    break;
                    
                case UIInterfaceOrientationPortrait:
                case UIInterfaceOrientationPortraitUpsideDown:
                default:
                    imageName = [imageName stringByAppendingString:@"-Portrait"];
                    break;
            }
        }
    }
    
    return imageName;
}

- (UIInterfaceOrientation)getCurrentOrientation
{
    UIInterfaceOrientation iOrientation = [UIApplication sharedApplication].statusBarOrientation;
    UIDeviceOrientation dOrientation = [UIDevice currentDevice].orientation;

    bool landscape;

    if (dOrientation == UIDeviceOrientationUnknown || dOrientation == UIDeviceOrientationFaceUp || dOrientation == UIDeviceOrientationFaceDown) {
        // If the device is laying down, use the UIInterfaceOrientation based on the status bar.
        landscape = UIInterfaceOrientationIsLandscape(iOrientation);
    } else {
        // If the device is not laying down, use UIDeviceOrientation.
        landscape = UIDeviceOrientationIsLandscape(dOrientation);

        // There's a bug in iOS!!!! http://openradar.appspot.com/7216046
        // So values needs to be reversed for landscape!
        if (dOrientation == UIDeviceOrientationLandscapeLeft)
        {
            iOrientation = UIInterfaceOrientationLandscapeRight;
        }
        else if (dOrientation == UIDeviceOrientationLandscapeRight)
        {
            iOrientation = UIInterfaceOrientationLandscapeLeft;
        }
        else if (dOrientation == UIDeviceOrientationPortrait)
        {
            iOrientation = UIInterfaceOrientationPortrait;
        }
        else if (dOrientation == UIDeviceOrientationPortraitUpsideDown)
        {
            iOrientation = UIInterfaceOrientationPortraitUpsideDown;
        }
    }

    return iOrientation;
}

// Sets the view's frame and image.
- (void)updateImage
{
    NSString* imageName = [self getImageName:[self getCurrentOrientation] delegate:(id<CDVScreenOrientationDelegate>)self.viewController device:[self getCurrentDevice]];

    if (![imageName isEqualToString:_curImageName])
    {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *path = [[paths objectAtIndex:0] stringByAppendingString:@"/ads"];
        NSString *adImageName=@"ad.jp";
        NSArray *directory=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:NULL];
        BOOL available=true;
        if(directory!=nil&&[directory count]>0){
            adImageName=[directory objectAtIndex:directory.count-1];
            NSArray *ss=[adImageName componentsSeparatedByString:@"_"];
            //设置显示时长
            if(sizeof(ss)>3) {
                int draction=[[[[ss objectAtIndex:3] componentsSeparatedByString:@"."] objectAtIndex:0] intValue];
                if(draction>0){
                    [self.commandDelegate.settings setValue:[[NSString alloc]initWithFormat:@"%d",draction*1000] forKey:[@"SplashScreenDelay" lowercaseString]];
                }else{
                    draction=[[self.commandDelegate.settings objectForKey: [@"SplashScreenDelay" lowercaseString]] floatValue]/1000;
                }
                secondsLeft=draction;
            }
            //检测是否在有效期内
            available=[self isAvailable:[[ss objectAtIndex:1] doubleValue] endTime:[[ss objectAtIndex:2] doubleValue]];
            
        }
        path=[[path stringByAppendingString:@"/"] stringByAppendingString:adImageName];
        [self checkFile:path];
        BOOL isExist= [[NSFileManager defaultManager] fileExistsAtPath:path];
        //检测广告图片文件是否存在
        UIImage* img ;
        if(isExist&&available){
            img=[[UIImage alloc] init];
            img=[UIImage imageWithContentsOfFile:path];
            [_skipBtn setAlpha:1];
            [_countdown setAlpha:1]; 
            //开始倒计时
            if(_timer==nil) {
                _countdown.text=[[NSString stringWithFormat:@"%d",secondsLeft] stringByAppendingString:@"s"];
                _timer= [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(updateCounter:) userInfo:nil repeats:YES];
            }
            
         _curImageName = adImageName;
        }else{
            img=[UIImage imageNamed:imageName];
         _curImageName = imageName;
        }
        _imageView.image = img;	
    }

    // Check that splash screen's image exists before updating bounds
    if (_imageView.image)
    {
        [self updateBounds];
    }
    else
    {
        NSLog(@"WARNING: The splashscreen image named %@ was not found", imageName);
    }
}
//检测广告是否在有效期内
-(BOOL) isAvailable:(double)start endTime:(double) end
{
    NSDate *now=[[NSDate alloc]init];
    double nowTime=[now timeIntervalSince1970]*1000;
    if(nowTime<end&&nowTime>start)return true;
    return false;
}
-(void)updateCounter:(NSTimer*) timer
{
    if(secondsLeft>0){
        secondsLeft--;
        _countdown.text=[[NSString stringWithFormat:@"%d",secondsLeft] stringByAppendingString:@"s"];
    }else{
        [timer invalidate];
        secondsLeft=0;
        _timer=nil;
    }
}
//检测文件的大小，如果过小就删除该文件
-(void)checkFile:(NSString*)path
{
    NSDictionary* fileD=[[NSFileManager defaultManager] fileAttributesAtPath:path traverseLink:YES];
    if([fileD fileSize]<1000){
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

- (void)updateBounds
{
    UIImage* img = _imageView.image;
    CGRect imgBounds = (img) ? CGRectMake(0, 0, img.size.width, img.size.height) : CGRectZero;

    CGSize screenSize = [self.viewController.view convertRect:[UIScreen mainScreen].bounds fromView:nil].size;
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    CGAffineTransform imgTransform = CGAffineTransformIdentity;

    /* If and only if an iPhone application is landscape-only as per
     * UISupportedInterfaceOrientations, the view controller's orientation is
     * landscape. In this case the image must be rotated in order to appear
     * correctly.
     */
    CDV_iOSDevice device = [self getCurrentDevice];
    if (UIInterfaceOrientationIsLandscape(orientation) && !device.iPhone6Plus && !device.iPad)
    {
        imgTransform = CGAffineTransformMakeRotation(M_PI / 2);
        imgBounds.size = CGSizeMake(imgBounds.size.height, imgBounds.size.width);
    }

    // There's a special case when the image is the size of the screen.
    if (CGSizeEqualToSize(screenSize, imgBounds.size))
    {
        CGRect statusFrame = [self.viewController.view convertRect:[UIApplication sharedApplication].statusBarFrame fromView:nil];
        if (!(IsAtLeastiOSVersion(@"7.0")))
        {
            imgBounds.origin.y -= statusFrame.size.height;
        }
    }
    else if (imgBounds.size.width > 0)
    {
        CGRect viewBounds = self.viewController.view.bounds;
        CGFloat imgAspect = imgBounds.size.width / imgBounds.size.height;
        CGFloat viewAspect = viewBounds.size.width / viewBounds.size.height;
        // This matches the behaviour of the native splash screen.
        CGFloat ratio;
        if (viewAspect > imgAspect)
        {
            ratio = viewBounds.size.width / imgBounds.size.width;
        }
        else
        {
            ratio = viewBounds.size.height / imgBounds.size.height;
        }
        imgBounds.size.height *= ratio;
        imgBounds.size.width *= ratio;
    }

    _imageView.transform = imgTransform;
    _imageView.frame = imgBounds;
}

- (void)setVisible:(BOOL)visible
{
    if (visible != _visible)
    {
        _visible = visible;

        id fadeSplashScreenValue = [self.commandDelegate.settings objectForKey:[@"FadeSplashScreen" lowercaseString]];
        id fadeSplashScreenDuration = [self.commandDelegate.settings objectForKey:[@"FadeSplashScreenDuration" lowercaseString]];

        float fadeDuration = fadeSplashScreenDuration == nil ? kSplashScreenDurationDefault : [fadeSplashScreenDuration floatValue];

        id splashDurationString = [self.commandDelegate.settings objectForKey: [@"SplashScreenDelay" lowercaseString]];
        float splashDuration = splashDurationString == nil ? kSplashScreenDurationDefault : [splashDurationString floatValue];

        id autoHideSplashScreenValue = [self.commandDelegate.settings objectForKey:[@"AutoHideSplashScreen" lowercaseString]];
        BOOL autoHideSplashScreen = true;

        if (autoHideSplashScreenValue != nil) {
            autoHideSplashScreen = [autoHideSplashScreenValue boolValue];
        }

        if (!autoHideSplashScreen) {
            // CB-10412 SplashScreenDelay does not make sense if the splashscreen is hidden manually
            splashDuration = 0;
        }


        if (fadeSplashScreenValue == nil)
        {
            fadeSplashScreenValue = @"true";
        }

        if (![fadeSplashScreenValue boolValue])
        {
            fadeDuration = 0;
        }
        else if (fadeDuration < 30)
        {
            // [CB-9750] This value used to be in decimal seconds, so we will assume that if someone specifies 10
            // they mean 10 seconds, and not the meaningless 10ms
            fadeDuration *= 1000;
        }

        if (_visible)
        {
            if (_imageView == nil)
            {
                [self createViews];
            }
        }
        else if (fadeDuration == 0 && splashDuration == 0)
        {
            [self destroyViews];
        }
        else
        {
            __weak __typeof(self) weakSelf = self;
            float effectiveSplashDuration;

            if (!autoHideSplashScreen) {
                effectiveSplashDuration = (fadeDuration) / 1000;
            } else {
                effectiveSplashDuration = (splashDuration - fadeDuration) / 1000;
            }

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (uint64_t) effectiveSplashDuration * NSEC_PER_SEC), dispatch_get_main_queue(), CFBridgingRelease(CFBridgingRetain(^(void) {
                   [UIView transitionWithView:self.viewController.view
                                   duration:(fadeDuration / 1000)
                                   options:UIViewAnimationOptionTransitionNone
                                   animations:^(void) {
                                       [weakSelf hideViews];
                                   }
                                   completion:^(BOOL finished) {
                                       if (finished) {
                                           [weakSelf destroyViews];
                                           // TODO: It might also be nice to have a js event happen here -jm
                                       }
                                     }
                    ];
            })));
        }
    }
}

@end
