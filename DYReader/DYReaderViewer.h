//
//  DYReaderViewer.h
//  DYReader
//
//  Created by oneko on 2022/6/30.
//

#import <UIKit/UIKit.h>

enum
{
    ResourceCacheMaxSize = 128<<20    /**< use at most 128M for resource cache */
};

NS_ASSUME_NONNULL_BEGIN

@interface DYReaderViewer : NSObject

@property (nonatomic, readonly) NSString *file;

- (BOOL)openFile:(NSString *)file;
- (UIView *)pageViewAt;

@end

NS_ASSUME_NONNULL_END
