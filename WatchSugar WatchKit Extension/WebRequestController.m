//
//  WebRequestController.m
//  WatchSugar
//
//  Created by Adam A. Wolf on 1/12/16.
//  Copyright © 2016 Flairify. All rights reserved.
//

#import "WebRequestController.h"
#import <ClockKit/ClockKit.h>

#import <AFNetworking/AFNetworking.h>

#import "DefaultsController.h"

static NSString *const kDexcomApplicationId_G5PlatinumApp = @"***REMOVED***";

NSString *const WSDefaults_LastReadings = @"WSDefaults_LastReadings";

@interface WebRequestController ()

@property (nonatomic, strong) dispatch_semaphore_t fetchSemaphore;

@end

@implementation WebRequestController

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.fetchSemaphore = dispatch_semaphore_create(0);
    }
    return self;
}

- (void)performFetch
{
    self.lastFetchAttempt = [NSDate date];
    
    [DefaultsController addLogMessage:@"performFetch"];

    NSDictionary * authenticationPayload = [self.authenticationController authenticationPayload];
    if (!authenticationPayload[@"accountName"] || !authenticationPayload[@"password"]) {
        [DefaultsController addLogMessage:@"watch app not authenitcated, skipping fetch attempt"];
        return;
    }
    
    //TODO: cache the dexcom token in user defaults, to avoid extra web requests when token would still be valid across instantiations of extensiondelegate
    
    if (!self.dexcomToken) {
        NSDictionary * authenticationPayload = [self.authenticationController authenticationPayload];
        [self authenticateWithDexcomAccountName:authenticationPayload[@"accountName"] andPassword:authenticationPayload[@"password"] shouldWait:NO];
    } else {
        [self fetchLatestBloodSugarAndWait:NO];
    }
}

- (void)performFetchAndWait
{
    [self performFetchAndWaitInternal];
    
    dispatch_semaphore_wait(self.fetchSemaphore, DISPATCH_TIME_FOREVER);
}

- (void)performFetchAndWaitInternal
{
    self.lastFetchAttempt = [NSDate date];
    
    [DefaultsController addLogMessage:@"performFetchAndWait"];
    
    NSDictionary * authenticationPayload = [self.authenticationController authenticationPayload];
    if (!authenticationPayload[@"accountName"] || !authenticationPayload[@"password"]) {
        [DefaultsController addLogMessage:@"watch app not authenitcated, skipping fetch attempt"];
        dispatch_semaphore_signal(self.fetchSemaphore);
        return;
    }
    
    //TODO: cache the dexcom token in user defaults, to avoid extra web requests when token would still be valid across instantiations of extensiondelegate
    
    if (!self.dexcomToken) {
        NSDictionary * authenticationPayload = [self.authenticationController authenticationPayload];
        [self authenticateWithDexcomAccountName:authenticationPayload[@"accountName"] andPassword:authenticationPayload[@"password"] shouldWait:YES];
    } else {
        [self fetchLatestBloodSugarAndWait:YES];
    }
}

+ (void)dexcomPOSTToURLString:(NSString *)URLString
               withParameters:(id)parameters
             withSuccessBlock:(void (^)(NSURLSessionDataTask *, id))success
             withFailureBlock:(void (^)(NSURLSessionDataTask *, NSError *))failure
                 shouldWait:(BOOL)shouldWait
{
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    if (shouldWait) {
        manager.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    }
    
    AFJSONRequestSerializer *requestSerializer = [AFJSONRequestSerializer serializer];
    [requestSerializer setValue:@"CGM-Store/4 CFNetwork/758.0.2 Darwin/15.0.0" forHTTPHeaderField:@"User-Agent"];
    [requestSerializer setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [manager setRequestSerializer:requestSerializer];
    
    AFJSONResponseSerializer *responseSerializer = [AFJSONResponseSerializer serializerWithReadingOptions:NSJSONReadingAllowFragments];
    [manager setResponseSerializer:responseSerializer];
    
    [manager POST:URLString parameters:parameters progress:NULL success:success failure:failure];
}

- (void)authenticateWithDexcomAccountName:(NSString *)accountName andPassword:(NSString *)password shouldWait:(BOOL)shouldWait
{
    NSString *URLString = @"https://share2.dexcom.com/ShareWebServices/Services/General/LoginPublisherAccountByName";
    NSDictionary *parameters = @{@"accountName": accountName,
                                 @"password": password,
                                 @"applicationId": kDexcomApplicationId_G5PlatinumApp};
    
    [WebRequestController dexcomPOSTToURLString:URLString
                                 withParameters:parameters
                               withSuccessBlock:^(NSURLSessionDataTask * task, id responseObject) {
                                   if (!shouldWait) {
                                       NSLog(@"received dexcom token: %@", responseObject);
                                   }
                                   self.dexcomToken = responseObject;
                                   
                                   if (!self.latestBloodSugarData) {
                                       [self fetchLatestBloodSugarAndWait:shouldWait];
                                   } else {
                                       dispatch_semaphore_signal(self.fetchSemaphore);
                                   }
                               }
                               withFailureBlock:^(NSURLSessionDataTask * task, NSError * error) {
                                   if (!shouldWait) {
                                       NSLog(@"error: %@", error);
                                   } else {
                                       dispatch_semaphore_signal(self.fetchSemaphore);
                                   }
                               }
                                     shouldWait:shouldWait];
}

- (void)fetchLatestBloodSugarAndWait:(BOOL)shouldWait
{
    [DefaultsController addLogMessage:[NSString stringWithFormat:@"fetchLatestBloodSugarAndWait:%@", shouldWait ? @"YES" : @"NO"]];
    
    NSString *URLString = [NSString stringWithFormat:@"https://share2.dexcom.com/ShareWebServices/Services/Publisher/ReadPublisherLatestGlucoseValues?sessionId=%@&minutes=1400&maxCount=1", self.dexcomToken];
    
    [WebRequestController dexcomPOSTToURLString:URLString
                                 withParameters:nil
                               withSuccessBlock:^(NSURLSessionDataTask * task, id responseObject) {
                                   if (!shouldWait) {
                                       NSLog(@"received blood sugar data: %@", responseObject);
                                   }
                                   [self setLatestBloodSugarData:responseObject[0] inBackground:shouldWait];
                               }
                               withFailureBlock:^(NSURLSessionDataTask * task, NSError * error) {
                                   NSDictionary *jsonError = [NSJSONSerialization JSONObjectWithData:error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] options:0 error:NULL];
                                   if (!shouldWait) {
                                       NSLog(@"error: %@", error);
                                       if (jsonError) {
                                           NSLog(@"error response: %@", jsonError);
                                       } else {
                                           NSString* errorString = [[NSString alloc] initWithData:(NSData *)error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] encoding:NSUTF8StringEncoding];
                                           NSLog(@"%@",errorString);
                                       }
                                   }
                                   
                                   if ([jsonError[@"Code"] isEqualToString:@"SessionNotValid"]) {
                                       self.dexcomToken = nil;
                                       self.latestBloodSugarData = nil;
                                       
                                       if (shouldWait) {
                                           [self performFetchAndWaitInternal];
                                       } else {
                                           [self performFetch];
                                       }
                                   } else {
                                       dispatch_semaphore_signal(self.fetchSemaphore);
                                   }
                               }
                                   shouldWait:shouldWait];
}

static const NSInteger kMaxReadings = 20;

-(void)setLatestBloodSugarData:(NSDictionary *)latestBloodSugarData inBackground:(BOOL)inBackground
{
    _latestBloodSugarData = latestBloodSugarData;
    
    if (_latestBloodSugarData) {
        NSArray *lastReadings = [[NSUserDefaults standardUserDefaults] arrayForKey:WSDefaults_LastReadings];
        lastReadings = lastReadings ? lastReadings : @[];
        NSDictionary *latestReading = [lastReadings lastObject];
        
        NSString *STDate = [_latestBloodSugarData[@"ST"] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"()"]][1];
        int64_t epochMilliseconds = [STDate longLongValue];
        if (!latestReading || [latestReading[@"timestamp"] longLongValue] != epochMilliseconds)
        {
            NSDictionary *newReading = @{
                                         @"timestamp": @(epochMilliseconds),
                                         @"trend": _latestBloodSugarData[@"Trend"],
                                         @"value": _latestBloodSugarData[@"Value"],
                                         };
            
            NSMutableArray *mutableLastReadings = [lastReadings mutableCopy];
            [mutableLastReadings addObject:newReading];
            
            while ([mutableLastReadings count] > kMaxReadings) {
                [mutableLastReadings removeObjectAtIndex:0];
            }
            
            [[NSUserDefaults standardUserDefaults] setObject:mutableLastReadings forKey:WSDefaults_LastReadings];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            [DefaultsController addLogMessage:[NSString stringWithFormat:@"Save COMPLETE setLatestBloodSugarData:%@ inBackground:%@", latestBloodSugarData, inBackground ? @"YES" : @"NO"]];
            
            if (!inBackground) {
                for (CLKComplication *complication in [[CLKComplicationServer sharedInstance] activeComplications]) {
                    [[CLKComplicationServer sharedInstance] reloadTimelineForComplication:complication];
                }
            }
            
            if (!inBackground) {
                [self.delegate webRequestControllerDidFetchNewBloodSugarData:self];
            }
            
        } else {
            [DefaultsController addLogMessage:[NSString stringWithFormat:@"Save skipped setLatestBloodSugarData:%@ inBackground:%@", latestBloodSugarData, inBackground ? @"YES" : @"NO"]];
            
            if (!inBackground) {
                NSLog(@"Latest Egv value has already been saved to Core Data. Skipping.");
            }
        }
    }
    
    if (inBackground) {
        dispatch_semaphore_signal(self.fetchSemaphore);
    }
}

@end
