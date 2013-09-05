//
//  GBAEmulationViewController.h
//  GBA4iOS
//
//  Created by Riley Testut on 7/19/13.
//  Copyright (c) 2013 Riley Testut. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "GBAController.h"
#import "GBAROM.h"

@interface GBAEmulationViewController : UIViewController

@property (readonly, nonatomic) GBAROM *rom;
@property (assign, nonatomic) CGFloat blurAlpha;
@property (assign, nonatomic) BOOL emulationPaused;

- (instancetype)initWithROM:(GBAROM *)rom;

- (void)blurWithInitialAlpha:(CGFloat)alpha;
- (void)removeBlur;

@end