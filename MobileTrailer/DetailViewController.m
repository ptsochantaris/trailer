//
//  DetailViewController.m
//  MobileTrailer
//
//  Created by Paul Tsochantaris on 4/1/14.
//  Copyright (c) 2014 HouseTrip. All rights reserved.
//

#import "DetailViewController.h"

@implementation DetailViewController

static DetailViewController *_detail_shared_ref;

+ (DetailViewController *)shared
{
	return _detail_shared_ref;
}

#pragma mark - Managing the detail item

- (void)setDetailItem:(id)newDetailItem
{
    if (_detailItem != newDetailItem) {
        _detailItem = newDetailItem;
        
        [self configureView];
    }

    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }        
}

- (void)configureView
{
	if (self.detailItem)
	{
		DLog(@"will load: %@",self.detailItem.webUrl);
		[self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self.detailItem.webUrl]]];
	}
	else
		[self.web loadHTMLString:@"" baseURL:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	_detail_shared_ref = self;
	[self configureView];
}

#pragma mark - Split view

- (void)splitViewController:(UISplitViewController *)splitController willHideViewController:(UIViewController *)viewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)popoverController
{
    barButtonItem.title = @"Pull Requests";
    [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    self.masterPopoverController = popoverController;
}

- (void)splitViewController:(UISplitViewController *)splitController willShowViewController:(UIViewController *)viewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    self.masterPopoverController = nil;
}

@end
