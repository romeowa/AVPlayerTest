//
//  AppDelegate.h
//  AVPlayerTest
//
//  Created by howard.han on 2017. 5. 29..
//  Copyright © 2017년 howard.han. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (readonly, strong) NSPersistentContainer *persistentContainer;

- (void)saveContext;


@end

