//
//  DYReaderViewer.m
//  DYReader
//
//  Created by oneko on 2022/6/30.
//

#import "DYBookReader.h"
#include "common.h"
#import "MuDocRef.h"
#import "DYPDFView.h"
#import "DYChapter.h"

static void flattenOutline(NSMutableArray *titles, NSMutableArray *pages, fz_outline *outline, int level)
{
    char indent[8*4+1];
    if (level > 8)
        level = 8;
    memset(indent, ' ', level * 4);
    indent[level * 4] = 0;
    while (outline)
    {
        int page = outline->page;
        if (page >= 0 && outline->title)
        {
            NSString *title = @(outline->title);
            [titles addObject: [NSString stringWithFormat: @"%s%@", indent, title]];
            [pages addObject: @(page)];
        }
        flattenOutline(titles, pages, outline->down, level + 1);
        outline = outline->next;
    }
}

@interface DYBookReader ()

@property (nonatomic, strong) MuDocRef *doc;
@property (nonatomic, copy) NSString *file;
@property (nonatomic, assign) int pageNum;
@property (nonatomic, strong) NSMutableArray *mChapterList;
@property (nonatomic, assign) int recordChapterIdx;
@property (nonatomic, assign) int recordPageIdx;
@property (nonatomic, copy) NSString *customCss;

@end

@implementation DYBookReader

- (instancetype)init {
    self = [super init];
    if (self) {
        self.fontSize = 18;
        self.mChapterList = [NSMutableArray array];
        [self initMupdf];
    }
    return self;
}

- (NSArray *)chapterList {
    return self.mChapterList;
}

- (void)layoutPageOutlines:(void (^)(void))completion {
    dispatch_async(queue, ^{
        NSString *ext = self.file.pathExtension;
        if ([ext.lowercaseString isEqualToString:@"pdf"]) {
            return;
        }
        
        fz_bookmark bookmark = fz_make_bookmark(ctx, self.doc->doc, self.pageIdx);
        [self onPasswordOkay];
        int findPage = fz_lookup_bookmark(ctx, self.doc->doc, bookmark);
        if (findPage >= 0) {
            self.pageIdx = findPage;
            for (int i = 0; i < self.chapterList.count; i++) {
                DYChapter *chapter = self.chapterList[i];
                if (chapter.pageIdx >= self.pageIdx) {
                    self.chapterIdx = i;
                    break;
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    });
}

- (void)updateFontSize:(CGFloat)fontSize completion:(void (^)(BOOL))completion {
    if (self.fontSize != fontSize) {
        self.fontSize = fontSize;
        
        [self layoutPageOutlines:^{
            completion(YES);
        }];
    } else {
        completion(NO);
    }
}

- (BOOL)openFile:(NSString *)file customCss:(NSString * _Nullable)customCss {
    self.customCss = customCss;
    self.pageNum = 0;
    [self.mChapterList removeAllObjects];
    
    self.file = file;
    self.doc = [[MuDocRef alloc] initWithFilename:file];
    if (!self.doc) {
        NSLog(@"Cannot open document: %@", file);
        return NO;
    }

    if (fz_needs_password(ctx, self.doc->doc)) {
        NSLog(@"file need password: %@", file);
        return NO;
    } else {
        [self onPasswordOkay];
        return YES;
    }
}

- (void)initMupdf {
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        queue = dispatch_queue_create("com.aggrx.mupdf.queue", NULL);
        ctx = fz_new_context(NULL, NULL, ResourceCacheMaxSize);
        fz_register_document_handlers(ctx);
        screenScale = [UIScreen mainScreen].scale;
    });
}

- (void)onPasswordOkay {
    fz_layout_document(ctx, self.doc->doc, self.pageSize.width, self.pageSize.height, self.fontSize);
    self.doc->doc->did_layout = 0;
    fz_outline *root = NULL;
    fz_try(ctx)
        root = fz_load_outline(ctx, self.doc->doc);
    fz_catch(ctx)
        root = NULL;
    if (self.customCss.length > 0) {
        fz_set_user_css(ctx, self.customCss.UTF8String);
        fz_set_use_document_css(ctx, 1);
    }
    
    if (root)
    {
        NSMutableArray *titles = [[NSMutableArray alloc] init];
        NSMutableArray *pages = [[NSMutableArray alloc] init];
        flattenOutline(titles, pages, root, 0);
        
        [self.mChapterList removeAllObjects];
        for (int i = 0; i < titles.count; i++) {
            DYChapter *chapter = [DYChapter chapterWithTitle:titles[i] page:[pages[i] intValue]];
            [self.mChapterList addObject:chapter];
        }
        self.pageNum = fz_count_pages(ctx, self.doc->doc);
        printf("book page: %d\n", self.pageNum);
        
        fz_drop_outline(ctx, root);
    }
}

- (UIView *)getPageViewAtPage:(int)pageIdx {
    DYPDFView *pdfView = [[DYPDFView alloc] initWithPage:pageIdx
                                                     doc:self.doc];
    return pdfView;
}

- (DYChapter *)getChapterAt:(int)index {
    if (index >= 0 && index < self.chapterList.count) {
        return self.chapterList[index];
    } else {
        return nil;
    }
}

- (BOOL)switchChapter:(int)index {
    if (index >= 0 && index < self.chapterList.count) {
        self.chapterIdx = index;
        
        DYChapter *chapter = self.chapterList[index];
        self.pageIdx = chapter.pageIdx;
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)switchToPage:(int)pageIdx
             chapter:(int)chapterIdx {
    if (chapterIdx >= 0 &&
        chapterIdx < self.chapterList.count &&
        pageIdx >= 0 &&
        pageIdx < self.pageNum) {
        self.pageIdx = pageIdx;
        self.chapterIdx = chapterIdx;
        NSLog(@"switch to page: %@, chapter: %@", @(pageIdx), @(chapterIdx));
        return YES;
    } else {
        return NO;
    }
}

- (void)recordCurrentChapter {
    self.recordChapterIdx = self.chapterIdx;
    self.recordPageIdx = self.pageIdx;
}

- (void)rollbackChapter {
    self.chapterIdx = self.recordChapterIdx;
    self.pageIdx = self.recordPageIdx;
}

- (int)getChapterIndexWithPageIndex:(int)pageIndex {
    int chapterIndex = 0;
    for (int i = 0; i < self.chapterList.count; i++) {
        DYChapter *chapter = self.chapterList[i];
        if (chapter.pageIdx >= pageIndex) {
            chapterIndex = i;
            break;
        }
    }
    return chapterIndex;
}

- (int)chapterIndexWithProgress:(float)progress {
    if (self.chapterList.count > 0) {
        return (int)((self.chapterList.count - 1) * progress);
    } else {
        return 0;
    }
}

- (float)chapterProgress:(int)chapterIndex {
    if (self.chapterList.count > 0) {
        return (float)chapterIndex / (float)(self.chapterList.count - 1);
    } else {
        return 0;
    }
}

- (BOOL)isValidPageIndex:(int)pageIndex {
    return pageIndex >= 0 && pageIndex < self.pageNum;
}

- (BOOL)isValidChapterIndex:(int)chapterIndex {
    return chapterIndex >= 0 && chapterIndex < self.chapterList.count;
}

@end
