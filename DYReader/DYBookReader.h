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

@protocol DYBookReaderProtocol <NSObject>

@property (nonatomic, readonly) NSString *file;
@property (nonatomic, readonly) int pageNum;
@property (nonatomic, readonly) NSArray *chapterList;
@property (nonatomic, assign) int chapterIdx;
@property (nonatomic, assign) int pageIdx;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) CGSize pageSize;

- (void)openFile:(NSString *)file completion:(void (^)(BOOL))completion;
- (UIView *)getPageViewAtPage:(int)pageIdx;
- (DYChapter * __nullable)getChapterAt:(int)index;
- (BOOL)switchChapter:(int)index;
- (BOOL)switchToPage:(int)pageIdx
             chapter:(int)chapterIdx;
- (void)layoutPageOutlines:(void (^)(void))completion;
- (void)updateFontSize:(CGFloat)fontSize completion:(void (^)(BOOL))completion;
/**
 * 记录切换前的章节
 */
- (void)recordCurrentChapter;
/**
 * 还原切换前的章节
 */
- (void)rollbackChapter;
/**
 * 按照页码查找章节码
 */
- (int)getChapterIndexWithPageIndex:(int)pageIndex;
/**
 * 按百分比取章节
 */
- (int)chapterIndexWithProgress:(float)progress;
/**
 * 章节的百分比
 */
- (float)chapterProgress:(int)chapterIndex;
/**
 * 页面是否有效
 */
- (BOOL)isValidPageIndex:(int)pageIndex;
/**
 * 章节是否有效
 */
- (BOOL)isValidChapterIndex:(int)chapterIndex;

@end

@interface DYBookReader : NSObject <DYBookReaderProtocol>

@property (nonatomic, readonly) NSString *file;
@property (nonatomic, readonly) int pageNum;
@property (nonatomic, readonly) NSArray *chapterList;
@property (nonatomic, assign) int chapterIdx;
@property (nonatomic, assign) int pageIdx;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) CGSize pageSize;
@property (nonatomic, copy) NSString *customCss;

- (void)openFile:(NSString *)file completion:(void (^)(BOOL))completion;
- (UIView *)getPageViewAtPage:(int)pageIdx;
- (DYChapter * __nullable)getChapterAt:(int)index;
- (BOOL)switchChapter:(int)index;
- (BOOL)switchToPage:(int)pageIdx
             chapter:(int)chapterIdx;
- (void)layoutPageOutlines:(void (^)(void))completion;
- (void)updateFontSize:(CGFloat)fontSize completion:(void (^)(BOOL))completion;
/**
 * 记录切换前的章节
 */
- (void)recordCurrentChapter;
/**
 * 还原切换前的章节
 */
- (void)rollbackChapter;
/**
 * 按照页码查找章节码
 */
- (int)getChapterIndexWithPageIndex:(int)pageIndex;
/**
 * 按百分比取章节
 */
- (int)chapterIndexWithProgress:(float)progress;
/**
 * 章节的百分比
 */
- (float)chapterProgress:(int)chapterIndex;
/**
 * 页面是否有效
 */
- (BOOL)isValidPageIndex:(int)pageIndex;
/**
 * 章节是否有效
 */
- (BOOL)isValidChapterIndex:(int)chapterIndex;

@end

NS_ASSUME_NONNULL_END
