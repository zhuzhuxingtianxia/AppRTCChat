//
//  ViewController.m
//  AppRTCChat
//
//  Created by Jion on 2017/11/20.
//  Copyright © 2017年 Jion. All rights reserved.
//
#import <AVFoundation/AVFoundation.h>
#import "ViewController.h"
#import "VideoChatController.h"
@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextField *roomNumberField;
@property (weak, nonatomic) IBOutlet UIButton *jionButton;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
}

- (IBAction)jionAction:(id)sender {
    VideoChatController *chatVC = [[VideoChatController alloc]init];
    chatVC.roomNumber = self.roomNumberField.text;
    [self presentViewController:chatVC animated:YES completion:nil];
}

#pragma mark - UITextFieldDelegate Methods
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string{
    BOOL isBackspace = [string isEqualToString:@""] && range.length == 1;
    NSString *text = [NSString stringWithFormat:@"%@%@", textField.text, string];
    if (isBackspace && text.length > 1) {
        text = [text substringWithRange:NSMakeRange(0, text.length-2)];
    }
    if (text.length >= 3) {
        [UIView animateWithDuration:0.3f animations:^{
            
            [self.jionButton setBackgroundColor:[UIColor colorWithRed:66.0f/255.0f green:133.0f/255.0f blue:244.0f/255.0f alpha:1.0f]];
            [self.jionButton setEnabled:YES];
            
        }];
    } else {
        [UIView animateWithDuration:0.3f animations:^{
            [self.jionButton setBackgroundColor:[UIColor colorWithWhite:100.0f/255.0f alpha:1.0f]];
            [self.jionButton setEnabled:NO];
            
        }];
    }
    return YES;
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
