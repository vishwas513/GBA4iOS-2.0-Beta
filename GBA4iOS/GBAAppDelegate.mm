//
//  GBAAppDelegate.m
//  GBA4iOS
//
//  Created by Riley Testut on 7/18/13.
//  Copyright (c) 2013 Riley Testut. All rights reserved.
//

#import "GBAAppDelegate.h"
#import "GBAEmulationViewController.h"
#import "GBASettingsViewController.h"
#import "GBAControllerSkin.h"
#import "GBAROM.h"
#import "GBASplitViewController.h"
#import "UIAlertView+RSTAdditions.h"

#import "SSZipArchive.h"
#import <DropboxSDK/DropboxSDK.h>
#import <AFNetworking/AFNetworkActivityIndicatorManager.h>

#import "UIView+DTDebug.h"

#if !(TARGET_IPHONE_SIMULATOR)
#import <CrashReporter/CrashReporter.h>
#import <Crashlytics/Crashlytics.h>
#endif

NSString * const GBAUserRequestedToPlayROMNotification = @"GBAUserRequestedToPlayROMNotification";

static void * GBAApplicationCrashedContext = &GBAApplicationCrashedContext;

static GBAAppDelegate *_appDelegate;

@interface GBAAppDelegate ()

@property (strong, nonatomic) GBAEmulationViewController *emulationViewController;

@end

@implementation GBAAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    _appDelegate = self;
    
    [UIView toggleViewMainThreadChecking];
    
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"showedWarningAlert"])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Welcome to GBA4iOS 2.0!", @"")
                                                            message:NSLocalizedString(@"If at any time the app fails to open, please set the date back on your device to before February 10, 2014, then try opening the app again. Once the app is opened, you can set the date back to the correct time, and the app will continue to open normally. However, you'll need to repeat this process every time you restart your device.", @"")
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
        });
        
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"showedWarningAlert"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
        
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.tintColor = GBA4iOS_PURPLE_COLOR;
    
    [[UISwitch appearance] setOnTintColor:GBA4iOS_PURPLE_COLOR]; // Apparently UISwitches don't inherit tint color from superview
    
    NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
    
    if (url)
    {
        if ([url isFileURL])
        {
            [self handleFileURL:url];
        }
        else
        {
            [self handleURLSchemeURL:url];
        }
    }
    
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
        
        self.emulationViewController = [[GBAEmulationViewController alloc] init];
        
        self.window.rootViewController = self.emulationViewController;
    }
    else
    {
        GBASplitViewController *splitViewController = [[GBASplitViewController alloc] init];
        self.window.rootViewController = splitViewController;
        
        self.emulationViewController = splitViewController.emulationViewController;
    }
    
    [[AFNetworkActivityIndicatorManager sharedManager] setEnabled:YES];
    
    [GBASettingsViewController registerDefaults];
    
#if !(TARGET_IPHONE_SIMULATOR)
    
#warning Uncomment for release, and comment out Crashlytics. Can't have both at once :(
    //[self setUpCrashCallbacks];
    [Crashlytics startWithAPIKey:@"d542629b4f6625cfd5564d27318550321272076d"];
        
#endif
    
    [self.window makeKeyAndVisible];
    
    [self.emulationViewController showSplashScreen];
    
    return YES;
}

- (void)renameUniqueFoldersToNamedFoldersInDirectory:(NSString *)directory
{
    // NSDirectoryEnumerator raises exception if URL is nil
    if ([[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:nil])
    {
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:directory]
                                                                 includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                                                    options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                               errorHandler:^BOOL(NSURL *url, NSError *error)
                                             {
                                                 NSLog(@"[Error] %@ (%@)", error, url);
                                                 return YES;
                                             }];
        
        
        for (NSURL *fileURL in enumerator)
        {
            [enumerator skipDescendants];
            
            NSString *filename;
            [fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil];
            
            NSNumber *isDirectory;
            [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
            
            DLog(@"%@", filename);
            
            if ([isDirectory boolValue])
            {
                GBAROM *rom = [GBAROM romWithUniqueName:filename];
                
                if (rom == nil)
                {
                    continue;
                }
                
                NSString *destinationPath = [[fileURL.path stringByDeletingLastPathComponent] stringByAppendingPathComponent:rom.name];
                
                if ([[NSFileManager defaultManager] fileExistsAtPath:destinationPath])
                {
                    [[NSFileManager defaultManager] replaceItemAtURL:[NSURL fileURLWithPath:destinationPath] withItemAtURL:fileURL backupItemName:nil options:0 resultingItemURL:nil error:nil];
                }
                else
                {
                    [[NSFileManager defaultManager] moveItemAtPath:fileURL.path toPath:destinationPath error:nil];
                }
            }
        }
    }
}

-(BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if ([url isFileURL])
    {
        [self handleFileURL:url];
    }
    else
    {
        return [self handleURLSchemeURL:url];
    }
    return YES;
}

- (void)handleFileURL:(NSURL *)url
{
    NSString *filepath = [url path];
    
    if ([[[filepath pathExtension] lowercaseString] isEqualToString:@"gbaskin"] || [[[filepath pathExtension] lowercaseString] isEqualToString:@"gbcskin"])
    {
        [self copySkinAtPathToDocumentsDirectory:filepath];
    }
    else if ([[[filepath pathExtension] lowercaseString] isEqualToString:@"zip"] ||
             [[[filepath pathExtension] lowercaseString] isEqualToString:@"gba"] ||
             [[[filepath pathExtension] lowercaseString] isEqualToString:@"gbc"] ||
             [[[filepath pathExtension] lowercaseString] isEqualToString:@"gb"])
    {
        [self copyROMAtPathToDocumentsDirectory:filepath];
    }
    
    // Empty Inbox folder
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[filepath stringByDeletingLastPathComponent] error:nil];
    for (NSString *filename in contents)
    {
        NSString *path = [[filepath stringByDeletingLastPathComponent] stringByAppendingPathComponent:filename];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

- (BOOL)handleURLSchemeURL:(NSURL *)url
{
    if ([[url scheme] hasPrefix:@"db"])
    {
        BOOL successful = NO;
        
        if ([[DBSession sharedSession] handleOpenURL:url])
        {
            successful = [[DBSession sharedSession] isLinked];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:GBASettingsDropboxStatusChangedNotification object:self userInfo:nil];
        
        return successful;
    }
    
    if ([[[url scheme] lowercaseString] isEqual:@"gba4ios"])
    {
        NSString *name = [[url host] stringByRemovingPercentEncoding];
        
        GBAROM *rom = [GBAROM romWithName:name];
        
        if (rom)
        {
            // Next run loop
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:GBAUserRequestedToPlayROMNotification object:rom userInfo:nil];
            });
            return YES;
        }
        
        rom = [GBAROM romWithUniqueName:name];
        
        if (rom)
        {
            // Next run loop
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:GBAUserRequestedToPlayROMNotification object:rom userInfo:nil];
            });
            return YES;
        }
        
        return NO;
    }
    
    return YES;
}

#pragma mark - Copying Files

- (void)copyROMAtPathToDocumentsDirectory:(NSString *)filepath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    
    if ([[[filepath pathExtension] lowercaseString] isEqualToString:@"zip"])
    {
        NSError *error = nil;
        [GBAROM unzipROMAtPathToROMDirectory:filepath withPreferredROMTitle:nil error:&error];
        
        if (error && [error code] == NSFileWriteFileExistsError)
        {
            
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"File Already Exists", @"")
                                                            message:NSLocalizedString(@"Please rename the existing file and try again.", @"")
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"Dismiss", @"") otherButtonTitles:nil];
            [alert show];
            
        }
        
        [[NSFileManager defaultManager] removeItemAtPath:filepath error:nil];
    }
    else
    {
        NSString *filename = [filepath lastPathComponent];
        
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documentsDirectory error:nil];
        
        BOOL fileExists = NO;
        
        for (NSString *item in contents)
        {
            if ([[[item pathExtension] lowercaseString] isEqualToString:@"gba"] || [[[item pathExtension] lowercaseString] isEqualToString:@"gbc"] ||
                [[[item pathExtension] lowercaseString] isEqualToString:@"gb"] || [[[item pathExtension] lowercaseString] isEqualToString:@"zip"])
            {
                NSString *name = [item stringByDeletingPathExtension];
                NSString *newFilename = [filename stringByDeletingPathExtension];
                
                if ([name isEqualToString:newFilename])
                {
                    fileExists = YES;
                    break;
                }
            }
        }
        
        if (fileExists)
        {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"File Already Exists", @"")
                                                            message:NSLocalizedString(@"Please rename either the existing file or the file to be imported and try again.", @"")
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"Dismiss", @"") otherButtonTitles:nil];
            [alert show];
            
            [[NSFileManager defaultManager] removeItemAtPath:filepath error:nil];
        }
        else
        {
            [[NSFileManager defaultManager] moveItemAtPath:filepath toPath:[documentsDirectory stringByAppendingPathComponent:filename] error:nil];
        }
    }
}

- (void)copySkinAtPathToDocumentsDirectory:(NSString *)filepath
{
    [GBAControllerSkin extractSkinAtPathToSkinsDirectory:filepath];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    
    [[NSFileManager defaultManager] removeItemAtPath:filepath error:nil];
}

#pragma mark - Application Crashes

void applicationDidCrash(siginfo_t *info, ucontext_t *uap, void *context)
{
    [_appDelegate.emulationViewController autoSaveIfPossible];
}

- (void)setUpCrashCallbacks
{
    
#if !(TARGET_IPHONE_SIMULATOR)
    PLCrashReporter *crashReporter = [PLCrashReporter sharedReporter];
    
    // Not interested in actual crashes; we use Crashlytics for that.
    [crashReporter purgePendingCrashReport];
    
    PLCrashReporterCallbacks callbacks = {
        .version = 0,
        .context = GBAApplicationCrashedContext,
        .handleSignal = applicationDidCrash
    };
    
    [crashReporter setCrashCallbacks:&callbacks];
    
    NSError *error = nil;
    
    if (![crashReporter enableCrashReporterAndReturnError: &error])
    {
        DLog(@"Error loading crash reporter: %@", error);
    }
    
#endif
}

#pragma mark - UIApplicationDelegate

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
