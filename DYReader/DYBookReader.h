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

@class DYChapter;

NS_ASSUME_NONNULL_BEGIN

@interface DYBookReader : NSObject

@property (nonatomic, readonly) NSString *file;
@property (nonatomic, readonly) int pageNum;
@property (nonatomic, readonly) NSArray *chapterList;
@property (nonatomic, assign) int chapterIdx;
@property (nonatomic, assign) int pageIdx;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) CGSize pageSize;

- (BOOL)openFile:(NSString *)file customCss:(NSString * __nullable)customCss;
- (UIView *)getPageViewAtPage:(int)pageIdx;
- (DYChapter * __nullable)getChapterAt:(int)index;
- (BOOL)switchChapter:(int)index;
- (BOOL)switchToPage:(int)pageIdx
             chapter:(int)chapterIdx;
- (void)layoutPageOutlines;
- (BOOL)updateFontSize:(CGFloat)fontSize;
/**
 * 记录切换前的章节
 */
- (void)recordCurrentChapter;
/**
 * 还原切换前的章节
 */
- (void)rollbackChapter;

@end

NS_ASSUME_NONNULL_END
