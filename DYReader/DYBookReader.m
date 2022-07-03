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

@end

@implementation DYBookReader

- (instancetype)init {
    self = [super init];
    if (self) {
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

- (UIView *)getPageViewAtPage:(int)pageIdx
                         size:(CGSize)size {
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    DYPDFView *pdfView = [[DYPDFView alloc] initWithFrame:rect
                                                     page:pageIdx
                                                      doc:self.doc];
    return pdfView;
}



@end
