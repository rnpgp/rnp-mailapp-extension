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

- (instancetype)initWithPubFormat:(const char *)pub_format secFormat:(const char *)sec_format;

@end

NS_ASSUME_NONNULL_END
