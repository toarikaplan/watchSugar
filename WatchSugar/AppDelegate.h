//
//  AppDelegate.h
//  WatchSugar
//
//  Created by Adam A. Wolf on 12/14/15.
//  Copyright © 2015 Flairify. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString *const WSNotificationDexcomDataChanged;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (nonatomic, strong) NSString *dexcomToken;
@property (nonatomic, strong) NSString *subscriptionId;
@property (nonatomic, strong) NSDictionary * latestBloodSugarData;

@end

