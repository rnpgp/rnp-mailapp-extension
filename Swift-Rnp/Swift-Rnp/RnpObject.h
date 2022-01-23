//
//  RnpObject.h
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 19.12.2021.
//

#import <Foundation/Foundation.h>
#import "rnp_shared.h"

NS_ASSUME_NONNULL_BEGIN

@interface RnpObject : NSObject

@property (nonatomic, assign) BOOL hasKeys;

- (instancetype)initWithPubFormat:(NSString *)pub_format secFormat:(NSString *)sec_format;
- (void)createKeys:(NSString *)userId password:(NSString *)password completion:(void (^)(BOOL)) completion;
- (nullable NSString*)decryptUsingKeys:(BOOL)usekeys password:(nullable NSString *)password;

@end

NS_ASSUME_NONNULL_END
