//
//  WebRequestController.m
//  WatchSugar
//
//  Created by Adam A. Wolf on 1/16/16.
//  Copyright © 2016 Flairify. All rights reserved.
//

#import "WebRequestController.h"

#import <AFNetworking/AFNetworking.h>

static NSString *const kDexcomApplicationId_G5PlatinumApp = @"***REMOVED***";

static NSString *const WSDexcomErrorCode_AccountNotFound = @"SSO_AuthenticateAccountNotFound";
static NSString *const WSDexcomErrorCode_InvalidPassword = @"SSO_AuthenticatePasswordInvalid";
static NSString *const WSDexcomErrorCode_MaxAttemptsExceeded = @"SSO_AuthenticateMaxAttemptsExceeed"; //"please try again in 10 minutes"

@interface WebRequestController ()

@end

@implementation WebRequestController

- (void)authenticateWithDexcomAccountName:(NSString *)accountName andPassword:(NSString *)password
{
    NSString *URLString = @"https://share2.dexcom.com/ShareWebServices/Services/General/LoginPublisherAccountByName";
    NSDictionary *parameters = @{@"accountName": accountName,
                                 @"password": password,
                                 @"applicationId": kDexcomApplicationId_G5PlatinumApp};
    
    [WebRequestController dexcomPOSTToURLString:URLString
                                 withParameters:parameters
                               withSuccessBlock:^(NSURLSessionDataTask * task, id responseObject) {
                                   [self.delegate webRequestController:self authenticationDidSucceedWithToken:responseObject];
                               }
                               withFailureBlock:^(NSURLSessionDataTask * task, NSError * error) {
                                   NSDictionary *errorResponse = [NSJSONSerialization JSONObjectWithData:error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] options:0 error:NULL];
                                   
                                   WebRequestControllerErrorCode errorCode = WebRequestControllerErrorCode_UnknownError;
                                   
                                   if (errorResponse && errorResponse[@"Code"]) {
                                       NSString *errorCodeString = errorResponse[@"Code"];

                                       if ([errorCodeString isEqualToString:WSDexcomErrorCode_AccountNotFound]) {
                                           errorCode = WebRequestControllerErrorCode_AccountNotFound;
                                       } else if ([errorCodeString isEqualToString:WSDexcomErrorCode_InvalidPassword]) {
                                           errorCode = WebRequestControllerErrorCode_InvalidPassword;
                                       } else if ([errorCodeString isEqualToString:WSDexcomErrorCode_MaxAttemptsExceeded]){
                                           errorCode = WebRequestControllerErrorCode_MaxAttemptsReached;
                                       }
                                   }
                                   
                                   [self.delegate webRequestController:self authenticationDidFailWithErrorCode:errorCode];
                               }];
}

- (void)readDexcomDisplayNameForToken:(NSString *)dexcomToken
{
    if (!dexcomToken) {
        [self.delegate webRequestController:self authenticationDidFailWithErrorCode:WebRequestControllerErrorCode_InvalidRequest];
        return;
    }
    
    NSString *URLString = [NSString stringWithFormat:@"https://share2.dexcom.com/ShareWebServices/Services/Publisher/ReadPublisherAccountDisplayName?sessionId=%@", dexcomToken];
    
    [WebRequestController dexcomPOSTToURLString:URLString
                                 withParameters:nil
                               withSuccessBlock:^(NSURLSessionDataTask * task, id responseObject) {
                                   [self.delegate webRequestController:self displayNameRequestDidSucceedWithName:responseObject];
                               }
                               withFailureBlock:^(NSURLSessionDataTask * task, NSError * error) {
                                   NSDictionary *errorResponse = [NSJSONSerialization JSONObjectWithData:error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] options:0 error:NULL];
                                   NSLog(@"readDexcomDisplayNameForToken failure with error response: %@", errorResponse);
                                   
                                   WebRequestControllerErrorCode errorCode = WebRequestControllerErrorCode_UnknownError;
                                   [self.delegate webRequestController:self displayNameRequestDidFailWithErrorCode:errorCode];
                               }];
}

- (void)readDexcomEmailForToken:(NSString *)dexcomToken
{
    if (!dexcomToken) {
        [self.delegate webRequestController:self authenticationDidFailWithErrorCode:WebRequestControllerErrorCode_InvalidRequest];
        return;
    }
    
    NSString *URLString = [NSString stringWithFormat:@"https://share2.dexcom.com/ShareWebServices/Services/Publisher/ReadPublisherAccountEmail?sessionId=%@", dexcomToken];
    
    [WebRequestController dexcomPOSTToURLString:URLString
                                 withParameters:nil
                               withSuccessBlock:^(NSURLSessionDataTask * task, id responseObject) {
                                   [self.delegate webRequestController:self emailRequestDidSucceedWithEmail:responseObject];
                               }
                               withFailureBlock:^(NSURLSessionDataTask * task, NSError * error) {
                                   NSDictionary *errorResponse = [NSJSONSerialization JSONObjectWithData:error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] options:0 error:NULL];
                                   NSLog(@"readDexcomEmailForToken failure with error response: %@", errorResponse);
                                   
                                   WebRequestControllerErrorCode errorCode = WebRequestControllerErrorCode_UnknownError;
                                   [self.delegate webRequestController:self emailRequestDidFailWithErrorCode:errorCode];
                               }];
}

#pragma mark - Static Helper methods

+ (void)dexcomPOSTToURLString:(NSString *)URLString
               withParameters:(id)parameters
             withSuccessBlock:(void (^)(NSURLSessionDataTask *, id))success
             withFailureBlock:(void (^)(NSURLSessionDataTask *, NSError *))failure
{
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];

    AFJSONRequestSerializer *requestSerializer = [AFJSONRequestSerializer serializer];
    [requestSerializer setValue:@"CGM-Store/4 CFNetwork/758.0.2 Darwin/15.0.0" forHTTPHeaderField:@"User-Agent"];
    [requestSerializer setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [manager setRequestSerializer:requestSerializer];
    
    AFJSONResponseSerializer *responseSerializer = [AFJSONResponseSerializer serializerWithReadingOptions:NSJSONReadingAllowFragments];
    [manager setResponseSerializer:responseSerializer];
    
    [manager POST:URLString parameters:parameters progress:NULL success:success failure:failure];
}

@end