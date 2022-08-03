//
//  DYPDFView.h
//  DYReader
//
//  Created by oneko on 2022/7/1.
//

#import <UIKit/UIKit.h>

@class MuDocRef;

NS_ASSUME_NONNULL_BEGIN

@interface DYPDFView : UIScrollView

- (instancetype)initWithPage:(int)pageIdx
                         doc:(MuDocRef *)docRef;

@end

NS_ASSUME_NONNULL_END
