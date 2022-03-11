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
        NSLog(@"Keys %@ present", object.hasKeys ? @"are" : @"isn't");
    }
    return 0;
}
