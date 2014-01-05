//
//  PreferencesViewController.h
//  Trailer
//
//  Created by Paul Tsochantaris on 4/1/14.
//  Copyright (c) 2014 HouseTrip. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface PreferencesViewController : UIViewController

@property (weak, nonatomic) IBOutlet UIProgressView *apiLoad;
@property (weak, nonatomic) IBOutlet UITextField *githubApiToken;
@property (weak, nonatomic) IBOutlet UILabel *versionNumber;
@property (weak, nonatomic) IBOutlet UITableView *repositories;
@property (weak, nonatomic) IBOutlet UIButton *refreshRepoList;

@property (strong, nonatomic) NSFetchedResultsController *fetchedResultsController;

@end
