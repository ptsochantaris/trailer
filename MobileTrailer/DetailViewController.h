//
//  DetailViewController.h
//  MobileTrailer
//
//  Created by Paul Tsochantaris on 4/1/14.
//  Copyright (c) 2014 HouseTrip. All rights reserved.
//

@interface DetailViewController : UIViewController
<UISplitViewControllerDelegate, UIWebViewDelegate, UIActionSheetDelegate>

@property (strong, nonatomic) PullRequest *detailItem;

@property (strong, nonatomic) UIPopoverController *masterPopoverController;
@property (weak, nonatomic) IBOutlet UIWebView *web;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *spinner;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *shareButton;
// copy link, open in safari

+ (DetailViewController *)shared;

@end
