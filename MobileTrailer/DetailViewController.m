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
		self.navigationItem.rightBarButtonItem.enabled = YES;
		[self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self.detailItem.webUrl]]];
		self.statusLabel.text = @"";
		self.statusLabel.hidden = YES;
	}
	else
	{
		[self setEmpty];
	}
}

- (void)setEmpty
{
	self.statusLabel.textColor = [UIColor lightGrayColor];
	self.statusLabel.text = @"Please select a Pull Request from the list on the left, or select 'Settings' to change your repository selection.\n\n(You may have to login to GitHub the first time you visit a page)";
	self.statusLabel.hidden = NO;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	self.title = nil;
	self.web.hidden = YES;
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

- (void)webViewDidStartLoad:(UIWebView *)webView
{
	[self.spinner startAnimating];
	self.statusLabel.hidden = YES;
	self.web.hidden = YES;
	self.title = @"Loading...";
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
	[self.spinner stopAnimating];
	self.statusLabel.hidden = YES;
	self.web.hidden = NO;
	self.title = self.detailItem.title;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
	[self.spinner stopAnimating];
	self.statusLabel.textColor = [UIColor redColor];
	self.statusLabel.text = [NSString stringWithFormat:@"There was an error loading this pull request page: %@",error];
	self.statusLabel.hidden = NO;
	self.web.hidden = YES;
	self.title = @"Error";
}

- (IBAction)iphoneShareButtonSelected:(UIBarButtonItem *)sender
{
	[[self shareSheet] showInView:self.view];
}
- (IBAction)ipadShareButtonSelected:(UIBarButtonItem *)sender
{
	[[self shareSheet] showFromBarButtonItem:sender animated:NO];
}
- (UIActionSheet *)shareSheet
{
	return [[UIActionSheet alloc] initWithTitle:self.title
									   delegate:self
							  cancelButtonTitle:@"Cancel"
						 destructiveButtonTitle:nil
							  otherButtonTitles:@"Copy Link", @"Open in Safari", nil];
}

- (void)actionSheet:(UIActionSheet *)actionSheet willDismissWithButtonIndex:(NSInteger)buttonIndex
{
	switch (buttonIndex) {
		case 0:
			[UIPasteboard generalPasteboard].string = self.web.request.URL.absoluteString;
			break;
		case 1:
			[[UIApplication sharedApplication] openURL:self.web.request.URL];
			break;
	}
}

@end
