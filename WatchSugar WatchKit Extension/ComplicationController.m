//
//  ComplicationController.m
//  WatchSugar WatchKit Extension
//
//  Created by Adam A. Wolf on 12/14/15.
//  Copyright © 2015 Flairify. All rights reserved.
//

#import "ComplicationController.h"

#import "ExtensionDelegate.h"

#import "DefaultsController.h"

#import "WatchWebRequestController.h"

static NSTimeInterval kBufferEGVToComplicationUpdate = 45.0f;
static NSTimeInterval kMinimumComplicationUpdateInterval = 9.0f * 60.0f;
static NSTimeInterval kEGVReadingInterval = 5.0f * 60.0f;

@interface ComplicationController ()

@end

@implementation ComplicationController

#pragma mark - Timeline Configuration

- (void)getSupportedTimeTravelDirectionsForComplication:(CLKComplication *)complication withHandler:(void(^)(CLKComplicationTimeTravelDirections directions))handler
{
    if ([DefaultsController timeTravelEnabled]) {
        handler(CLKComplicationTimeTravelDirectionBackward);
    } else {
        handler(CLKComplicationTimeTravelDirectionNone);
    }
}

- (void)getTimelineStartDateForComplication:(CLKComplication *)complication withHandler:(void(^)(NSDate *__nullable date))handler
{
    if (![DefaultsController timeTravelEnabled]) {
        handler(nil);
        return;
    }
    
    NSDate *date = [NSDate date];
    
    NSDictionary *earliestReading = [[DefaultsController latestBloodSugarReadings] firstObject];
    
    if (earliestReading) {
        NSTimeInterval earliestTimestamp = [earliestReading[@"timestamp"] doubleValue] / 1000.00;
        NSDate *earliestDate = [NSDate dateWithTimeIntervalSince1970:earliestTimestamp];
        date = earliestDate;
    }
    
    handler(date);
}

- (void)getTimelineEndDateForComplication:(CLKComplication *)complication withHandler:(void(^)(NSDate *__nullable date))handler
{
    handler(nil);
}

- (void)getPrivacyBehaviorForComplication:(CLKComplication *)complication withHandler:(void(^)(CLKComplicationPrivacyBehavior privacyBehavior))handler
{
    handler(CLKComplicationPrivacyBehaviorShowOnLockScreen);
}

#pragma mark - Timeline Population

+ (CLKComplicationTimelineEntry *)createTimelineEntryForReading:(NSDictionary *)reading forComplication:(CLKComplication *)complication
{
    NSString *bloodSugarValueString = @"--";
    UIImage *trendImage = [UIImage imageNamed:@"trend_0"];
    NSDate *timeStampAsDate = nil;
    NSTimeInterval epoch = 0.0f;
    
    if (reading && reading[@"trend"] && reading[@"value"]) {
        //valid reading
        int readingValue = [reading[@"value"] intValue];
        bloodSugarValueString = [NSString stringWithFormat:@"%d", readingValue];
        
        int readingTrend = [reading[@"trend"] intValue];
        NSString *trendImageName = [NSString stringWithFormat:@"trend_%d", readingTrend];
        trendImage = [UIImage imageNamed:trendImageName];
        
        epoch = [reading[@"timestamp"] doubleValue] / 1000.00; //dexcom dates include milliseconds
        timeStampAsDate = [NSDate dateWithTimeIntervalSince1970:epoch];
    } else if (reading) {
        //placeholder for non-fresh results
        bloodSugarValueString = @"---";
        
        epoch = [reading[@"timestamp"] doubleValue] / 1000.00; //dexcom dates include milliseconds
        timeStampAsDate = [NSDate dateWithTimeIntervalSince1970:epoch];
    } else {
        //no reading whatsoever
        timeStampAsDate = [NSDate date];
    }
    
    // Create the template and timeline entry.
    CLKImageProvider *smallTrendImageProvider = [CLKImageProvider imageProviderWithOnePieceImage:trendImage];
    CLKSimpleTextProvider *simpleTextProvider = [CLKSimpleTextProvider textProviderWithText:[NSString stringWithFormat:@"%@ mg/dL", bloodSugarValueString] shortText:bloodSugarValueString];
    
    CLKComplicationTimelineEntry *entry = nil;
    timeStampAsDate = timeStampAsDate ? timeStampAsDate : [NSDate date];
    if (complication.family == CLKComplicationFamilyModularSmall) {
        CLKComplicationTemplateModularSmallStackImage *smallStackImageTemplate = [[CLKComplicationTemplateModularSmallStackImage alloc] init];
        smallStackImageTemplate.line1ImageProvider = smallTrendImageProvider;
        smallStackImageTemplate.line2TextProvider = simpleTextProvider;
        
        entry = [CLKComplicationTimelineEntry entryWithDate:timeStampAsDate complicationTemplate:smallStackImageTemplate];
    } else if (complication.family == CLKComplicationFamilyCircularSmall) {
        CLKComplicationTemplateCircularSmallStackImage *smallStackImageTemplate = [[CLKComplicationTemplateCircularSmallStackImage alloc] init];
        smallStackImageTemplate.line1ImageProvider = smallTrendImageProvider;
        smallStackImageTemplate.line2TextProvider = simpleTextProvider;
        
        entry = [CLKComplicationTimelineEntry entryWithDate:timeStampAsDate complicationTemplate:smallStackImageTemplate];
    } else if (complication.family == CLKComplicationFamilyUtilitarianSmall) {
        CLKComplicationTemplateUtilitarianSmallFlat *smallFlatImageTemplate = [[CLKComplicationTemplateUtilitarianSmallFlat alloc] init];
        smallFlatImageTemplate.imageProvider = smallTrendImageProvider;
        smallFlatImageTemplate.textProvider = simpleTextProvider;
        
        entry = [CLKComplicationTimelineEntry entryWithDate:timeStampAsDate complicationTemplate:smallFlatImageTemplate];
    } else if (complication.family == CLKComplicationFamilyUtilitarianLarge) {
        CLKComplicationTemplateUtilitarianLargeFlat *largeFlatImageTemplate = [[CLKComplicationTemplateUtilitarianLargeFlat alloc] init];
        largeFlatImageTemplate.imageProvider = smallTrendImageProvider;
        largeFlatImageTemplate.textProvider = simpleTextProvider;
        
        entry = [CLKComplicationTimelineEntry entryWithDate:timeStampAsDate complicationTemplate:largeFlatImageTemplate];
    } else if (complication.family == CLKComplicationFamilyModularLarge) {
        CLKComplicationTemplateModularLargeStandardBody *standardBodyTemplate = [[CLKComplicationTemplateModularLargeStandardBody alloc] init];
        standardBodyTemplate.headerImageProvider = smallTrendImageProvider;
        standardBodyTemplate.headerTextProvider = simpleTextProvider;
        
        static NSDateFormatter *_timeStampDateFormatter = nil;
        if (!_timeStampDateFormatter) {
            _timeStampDateFormatter = [[NSDateFormatter alloc] init];
            _timeStampDateFormatter.dateFormat = @"M-d h:mm a";
        }
        NSString *dateString = [NSString stringWithFormat:@"from %@", [_timeStampDateFormatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:epoch]]];
        
        standardBodyTemplate.body1TextProvider = [CLKSimpleTextProvider textProviderWithText:dateString];
        
        entry = [CLKComplicationTimelineEntry entryWithDate:timeStampAsDate complicationTemplate:standardBodyTemplate];
    }
    
    return entry;
}

- (void)getCurrentTimelineEntryForComplication:(CLKComplication *)complication withHandler:(void(^)(CLKComplicationTimelineEntry *__nullable))handler
{
    NSDictionary *latestReading = [[DefaultsController latestBloodSugarReadings] lastObject];
    
    [DefaultsController addLogMessage:[NSString stringWithFormat:@"getCurrentTimelineEntryForComplication rendering %@", latestReading]];

    handler([ComplicationController createTimelineEntryForReading:latestReading forComplication:complication]);
}

- (void)getTimelineEntriesForComplication:(CLKComplication *)complication beforeDate:(NSDate *)date limit:(NSUInteger)limit withHandler:(void(^)(NSArray<CLKComplicationTimelineEntry *> *__nullable entries))handler
{
    if (![DefaultsController timeTravelEnabled]) {
        handler(nil);
        return;
    }
    
    NSTimeInterval latestAcceptableTimestamp = [date timeIntervalSince1970];
    
    NSMutableArray <CLKComplicationTimelineEntry *> *entries = [NSMutableArray new];
    
    NSArray <NSDictionary *> *latestReadings = [DefaultsController latestBloodSugarReadings];
    
    __block NSDictionary *eligibleReading = nil;
    [latestReadings enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSDictionary *currentReading, NSUInteger idx, BOOL *stop) {
        NSTimeInterval currentReadingTimestamp = [currentReading[@"timestamp"] doubleValue] / 1000.00;
        
        if (currentReading != [latestReadings lastObject] && currentReadingTimestamp < latestAcceptableTimestamp) {
            eligibleReading = currentReading;
            *stop = YES;
        }
    }];
    
    while (eligibleReading && entries.count < limit) {
        [entries addObject:[ComplicationController createTimelineEntryForReading:eligibleReading forComplication:complication]];
        
        NSInteger indexOfEligibleReading = [latestReadings indexOfObject:eligibleReading];
        if (indexOfEligibleReading > 0) {
            eligibleReading = latestReadings[indexOfEligibleReading - 1];
        } else {
            eligibleReading = nil;
        }
    }
    
    //[DefaultsController addLogMessage:[NSString stringWithFormat:@"getTimelineEntriesForComplication beforeDate:%@ limit:%d : %u returned", date, (int)limit, entries.count]];
    
    handler(entries);
}

- (void)getTimelineEntriesForComplication:(CLKComplication *)complication afterDate:(NSDate *)date limit:(NSUInteger)limit withHandler:(void(^)(NSArray<CLKComplicationTimelineEntry *> *__nullable entries))handler
{
    handler(nil);
}

#pragma mark Update Scheduling

#define kSecondsInMinute 60.0f
#define kSecondsPerHour (60.0f * kSecondsInMinute)
#define kHoursInDay 24.0f

- (void)getNextRequestedUpdateDateWithHandler:(void(^)(NSDate *__nullable updateDate))handler
{
    NSDate *futureDate = nil;
    
    //determine if we're in a quite time interval
    __block BOOL isQuietTime = NO;
    
    NSInteger quietStartHour = [DefaultsController quietTimeStartHour];
    NSInteger quietEndHour = [DefaultsController quietTimeEndHour];
    
    NSDate *now = [NSDate date];
    NSDate *startOfToday = [[NSCalendar currentCalendar] startOfDayForDate:now];
    
    NSMutableArray <NSDate *> *midnightsToCheck = [NSMutableArray new];
    [midnightsToCheck addObject:startOfToday];
    if (quietStartHour > quietEndHour) {
        //check tomorrow's midnight as well
        quietStartHour -= kHoursInDay;
        
        [midnightsToCheck addObject:[startOfToday dateByAddingTimeInterval:kHoursInDay * kSecondsPerHour]];
    }
    
    [midnightsToCheck enumerateObjectsUsingBlock:^(NSDate *midnight, NSUInteger idx, BOOL *stop) {
        NSDate *startQuietRange = [midnight dateByAddingTimeInterval:quietStartHour * kSecondsPerHour];
        NSDate *endQuietRange = [midnight dateByAddingTimeInterval:quietEndHour * kSecondsPerHour];
        
        if ([now timeIntervalSinceReferenceDate] > [startQuietRange timeIntervalSinceReferenceDate] &&
            [now timeIntervalSinceReferenceDate] < [endQuietRange timeIntervalSinceReferenceDate]) {
            isQuietTime = YES;
            *stop = YES;
        }
    }];
    
    if (!isQuietTime ) {
        //dexcom system captures an EGV every 5 minutes
        //knowing that, let's be smart about the complication update interval.
        //make it update 1) 45 seconds after an anticipated EGV reading and 2) no sooner than 9 minutes from now
        
        NSDictionary *latestReading = [[DefaultsController latestBloodSugarReadings] lastObject];
        if (!latestReading) {
            futureDate = [now dateByAddingTimeInterval:9.5 * kSecondsInMinute];
        } else {
            NSTimeInterval timestamp = [latestReading[@"timestamp"] doubleValue] / 1000.00;
            NSTimeInterval nextTimestamp = timestamp + kBufferEGVToComplicationUpdate;
            
            NSTimeInterval nineMinutesFromNowTimestamp = [[NSDate date] timeIntervalSince1970] + kMinimumComplicationUpdateInterval;
            while (nextTimestamp < nineMinutesFromNowTimestamp) {
                nextTimestamp += kEGVReadingInterval;
            }
            
            futureDate = [NSDate dateWithTimeIntervalSince1970:nextTimestamp];
        }
    } else {
        [DefaultsController addLogMessage:@"getNextRequestedUpdateDateWithHandler in quietTime. Requesting less frequent updates..."];
        futureDate = [now dateByAddingTimeInterval:50 * kSecondsInMinute];
    }
    
    static NSDateFormatter *_timeStampDateFormatter = nil;
    if (!_timeStampDateFormatter) {
        _timeStampDateFormatter = [[NSDateFormatter alloc] init];
        _timeStampDateFormatter.dateStyle = NSDateFormatterShortStyle;
        _timeStampDateFormatter.timeStyle = NSDateFormatterMediumStyle;
    }
    
    [DefaultsController addLogMessage:[NSString stringWithFormat:@"getNextRequestedUpdateDateWithHandler requesting future date: %@", [_timeStampDateFormatter stringFromDate:futureDate]]];
    
    handler(futureDate);
}

- (void)requestedUpdateDidBegin
{
    [DefaultsController configureDefaults];
    
    [DefaultsController addLogMessage:@"ComplicationController requestedUpdateDidBegin"];
    
    NSDictionary *previousLatestReading = [[DefaultsController latestBloodSugarReadings] lastObject];
    
    // Get the current complication data from the extension delegate.
    ExtensionDelegate *extensionDelegate = (ExtensionDelegate *)[WKExtension sharedExtension].delegate;
    if (!extensionDelegate.webRequestController || !extensionDelegate.authenticationController) {
        [extensionDelegate initializeSubControllers];
        
        [DefaultsController addLogMessage:[NSString stringWithFormat:@"ComplicationController requestedUpdateDidBegin allocated: %@", extensionDelegate.webRequestController]];
    }
    
    WatchWebRequestController *webRequestController = extensionDelegate.webRequestController;
    
    if (!webRequestController.lastFetchAttempt || [[NSDate date] timeIntervalSinceDate:webRequestController.lastFetchAttempt] > 60.0f) {
        [webRequestController performFetchWhileWaiting:YES];
    }
    
    BOOL didChange = NO;
    
    NSDictionary *latestReading = [[DefaultsController latestBloodSugarReadings] lastObject];
    
    if (!previousLatestReading && latestReading) {
        didChange = YES;
    } else if (previousLatestReading && latestReading) {
        NSTimeInterval previousEpoch = [previousLatestReading[@"timestamp"] doubleValue] / 1000.00;
        NSTimeInterval latestEpoch = [latestReading[@"timestamp"] doubleValue] / 1000.00;
        
        didChange = previousEpoch != latestEpoch;
    }
    
    if (didChange) {
        [DefaultsController addLogMessage:@"ComplicationController requestedUpdateDidBegin didChange, updating complication"];
        
        for (CLKComplication *complication in [[CLKComplicationServer sharedInstance] activeComplications]) {
            [[CLKComplicationServer sharedInstance] reloadTimelineForComplication:complication];
        }
    }
}

- (void)requestedUpdateBudgetExhausted
{
    [DefaultsController addLogMessage:@"ComplicationController requestedUpdateBudgetExhausted!"];
}

#pragma mark - Placeholder Templates

- (void)getPlaceholderTemplateForComplication:(CLKComplication *)complication withHandler:(void(^)(CLKComplicationTemplate *__nullable complicationTemplate))handler
{
    // This method will be called once per supported complication, and the results will be cached
    
    CLKComplicationTemplate *template = nil;
    
    CLKImageProvider *smallTrendImageProvider = [CLKImageProvider imageProviderWithOnePieceImage:[UIImage imageNamed:@"trend_0"]];
    CLKSimpleTextProvider *simpleTextProvider = [CLKSimpleTextProvider textProviderWithText:@"-- mg/dL" shortText:@"--"];;
    
    // Create the template and timeline entry.
    if (complication.family == CLKComplicationFamilyModularSmall) {
        CLKComplicationTemplateModularSmallStackImage *smallStackImageTemplate = [[CLKComplicationTemplateModularSmallStackImage alloc] init];
        smallStackImageTemplate.line1ImageProvider = smallTrendImageProvider;
        smallStackImageTemplate.line2TextProvider = simpleTextProvider;
        
        template = smallStackImageTemplate;
    } else if (complication.family == CLKComplicationFamilyCircularSmall) {
        CLKComplicationTemplateCircularSmallStackImage *smallStackImageTemplate = [[CLKComplicationTemplateCircularSmallStackImage alloc] init];
        smallStackImageTemplate.line1ImageProvider = smallTrendImageProvider;
        smallStackImageTemplate.line2TextProvider = simpleTextProvider;
        
        template = smallStackImageTemplate;
    } else if (complication.family == CLKComplicationFamilyUtilitarianSmall) {
        CLKComplicationTemplateUtilitarianSmallFlat *smallFlatImageTemplate = [[CLKComplicationTemplateUtilitarianSmallFlat alloc] init];
        smallFlatImageTemplate.imageProvider = smallTrendImageProvider;
        smallFlatImageTemplate.textProvider = simpleTextProvider;
        
        template = smallFlatImageTemplate;
    } else if (complication.family == CLKComplicationFamilyUtilitarianLarge) {
        CLKComplicationTemplateUtilitarianLargeFlat *largeFlatImageTemplate = [[CLKComplicationTemplateUtilitarianLargeFlat alloc] init];
        largeFlatImageTemplate.imageProvider = smallTrendImageProvider;
        largeFlatImageTemplate.textProvider = simpleTextProvider;
        
        template = largeFlatImageTemplate;
    } else if (complication.family == CLKComplicationFamilyModularLarge) {
        CLKComplicationTemplateModularLargeStandardBody *standardBodyTemplate = [[CLKComplicationTemplateModularLargeStandardBody alloc] init];
        standardBodyTemplate.headerImageProvider = smallTrendImageProvider;
        standardBodyTemplate.headerTextProvider = simpleTextProvider;
        
        static NSDateFormatter *_timeStampDateFormatter = nil;
        if (!_timeStampDateFormatter) {
            _timeStampDateFormatter = [[NSDateFormatter alloc] init];
            _timeStampDateFormatter.dateFormat = @"M-d h:mm a";
        }
        NSString *dateString = [NSString stringWithFormat:@"from %@", [_timeStampDateFormatter stringFromDate:[NSDate date]]];
        
        standardBodyTemplate.body1TextProvider = [CLKSimpleTextProvider textProviderWithText:dateString];
        
        template = standardBodyTemplate;
    }
    
    handler(template);
}

@end
