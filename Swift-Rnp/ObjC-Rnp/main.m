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
        RNPLog(@"Keys %@ present", object.hasOwnKeys ? @"are" : @"isn't");
        
        NSString *userId = @"userId@key";
        NSString *password = @"userPass";
        NSError *error;
        if (!object.hasOwnKeys) {
            [object createKeys:userId password:password error:&error];
            if (error) {
                NSLog(@"%@", error);
            }
        }
        
        if (object.hasOwnKeys) {
            NSString *text = @"What a day!";
            
            NSString *message = [object encryptString:text userId:userId password:password error:&error];
            if (error) {
                NSLog(@"%@", error);
            }
            
            if (error == nil && message) {
                NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
                if (data) {
                    NSString *aMessage = [object decryptData:data password:password error:&error];
                    if (error) {
                        NSLog(@"Decoding error - %@", error);
                    }
                    if (aMessage) {
                        NSLog(@"encoded and decoded - %@", aMessage);
                    }
                } else {
                    NSLog(@"Conversion from string to data is fails");
                }
            }
        }
    }
    return 0;
}
