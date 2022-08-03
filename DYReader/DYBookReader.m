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

@end

@implementation DYBookReader

- (instancetype)init {
    self = [super init];
    if (self) {
        self.fontSize = 14;
        self.mChapterList = [NSMutableArray array];
        [self initMupdf];
    }
    return self;
}

- (NSArray *)chapterList {
    return self.mChapterList;
}

- (BOOL)openFile:(NSString *)file {
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
    fz_outline *root = NULL;
    fz_try(ctx)
        root = fz_load_outline(ctx, self.doc->doc);
    fz_catch(ctx)
        root = NULL;
    
    CGRect frame = UIApplication.sharedApplication.keyWindow.bounds;
    if (@available(iOS 11.0, *)) {
        UIEdgeInsets insets = UIApplication.sharedApplication.keyWindow.safeAreaInsets;
        frame = CGRectInset(frame, insets.left + insets.right, insets.top + insets.bottom);
    }
    
    fz_layout_document(ctx, self.doc->doc, frame.size.width, frame.size.height, self.fontSize);
    if (root)
    {
        NSMutableArray *titles = [[NSMutableArray alloc] init];
        NSMutableArray *pages = [[NSMutableArray alloc] init];
        flattenOutline(titles, pages, root, 0);
        
        for (int i = 0; i < titles.count; i++) {
            DYChapter *chapter = [DYChapter chapterWithTitle:titles[i] page:[pages[i] intValue]];
            [self.mChapterList addObject:chapter];
        }
        self.pageNum = fz_count_pages(ctx, self.doc->doc);
        
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

- (void)recordCurrentChapter {
    self.recordChapterIdx = self.chapterIdx;
    self.recordPageIdx = self.pageIdx;
}

- (void)rollbackChapter {
    self.chapterIdx = self.recordChapterIdx;
    self.pageIdx = self.recordPageIdx;
}

@end
