//
//  RnpObject.h
//  Swift-Rnp
//
//  Created by Sergey Vinogradov on 19.12.2021.
//

#import <Foundation/Foundation.h>
#include "rnp.h"
#include "rnp_err.h"

NS_ASSUME_NONNULL_BEGIN

@interface RnpObject : NSObject

@property (nonatomic, assign) BOOL hasKeys;

- (instancetype)initWithPubFormat:(NSString *)pub_format secFormat:(NSString *)sec_format;
- (void)createKeys:(NSString *)userId password:(NSString *)password completion:(void (^)(BOOL)) completion;
//- (NSString *)decrypt:(BOOL)useKeys;

@end

NS_ASSUME_NONNULL_END
