//
//  main.m
//  ObjC-Rnp
//
//  Created by Sergey Vinogradov on 06.03.2022.
//

#import <Foundation/Foundation.h>
#import <RNPFramework_MacOS_Intel/RNPFramework_MacOS_Intel.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *format = [RnpConstants RnpKeyStoreFormat_toString: kRnpKeyStoreFormatGPG];
        RnpObject* object = [[RnpObject alloc] initWithPubFormat:format secFormat:format];
        NSLog(@"Keys %@ present", object.hasOwnKeys ? @"are" : @"isn't");
        
        NSString *userId = @"userId@key";
        NSString *password = @"userPass";
        if (object.hasOwnKeys) {
            NSString *text = @"What a day!";
            
            NSString *message = [object encryptString:text userId:userId password:password];
            if (message) {
                NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
                if (data) {
                    NSString *aMessage = [object decryptData:data usingKeys:false password:password];
                    if (aMessage) {
                        NSLog(@"encoded and decoded - %@", aMessage);
                    } else {
                        NSLog(@"Decoding error");
                    }
                } else {
                    NSLog(@"Conversion from string to data is fails");
                }
            } else {
                NSLog(@"Encoding error");
            }
        } else {
            [object createKeys:userId password:password completion:^(BOOL success) {
                NSLog(@"Keys are %@",success ? @"generated" : @"not generated");
            }];
        }
    }
    return 0;
}
