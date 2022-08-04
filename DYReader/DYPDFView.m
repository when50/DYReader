//
//  DYPDFView.m
//  DYReader
//
//  Created by oneko on 2022/7/1.
//

#import "DYPDFView.h"
#include "common.h"
#include "mupdf/pdf.h"
#import "MuDocRef.h"
#import "MuAnnotation.h"

static UIImage *newImageWithPixmap(fz_pixmap *pix, CGDataProviderRef cgdata)
{
    CGImageRef cgimage = CreateCGImageWithPixmap(pix, cgdata);
    UIImage *image = [[UIImage alloc] initWithCGImage: cgimage scale: screenScale orientation: UIImageOrientationUp];
    CGImageRelease(cgimage);
    return image;
}

static NSArray *enumerateWidgetRects(fz_document *doc, fz_page *page)
{
    pdf_document *idoc = pdf_specifics(ctx, doc);
    pdf_widget *widget;
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:10];

    if (!idoc)
        return nil;

    for (widget = pdf_first_widget(ctx, idoc, (pdf_page *)page); widget; widget = pdf_next_widget(ctx, widget))
    {
        fz_rect rect;

        pdf_bound_widget(ctx, widget, &rect);
        [arr addObject:[NSValue valueWithCGRect:CGRectMake(
            rect.x0,
            rect.y0,
            rect.x1-rect.x0,
            rect.y1-rect.y0)]];
    }

    return arr;
}

static NSArray *enumerateAnnotations(fz_document *doc, fz_page *page)
{
    fz_annot *annot;
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:10];

    for (annot = fz_first_annot(ctx, page); annot; annot = fz_next_annot(ctx, annot))
        [arr addObject:[MuAnnotation annotFromAnnot:annot]];

    return arr;
}

static fz_display_list *create_page_list(fz_document *doc, fz_page *page)
{
    fz_display_list *list = NULL;
    fz_device *dev = NULL;

    fz_var(dev);
    fz_try(ctx)
    {
        list = fz_new_display_list(ctx, NULL);
        dev = fz_new_list_device(ctx, list);
        fz_run_page_contents(ctx, page, dev, &fz_identity, NULL);
        fz_close_device(ctx, dev);
    }
    fz_always(ctx)
    {
        fz_drop_device(ctx, dev);
    }
    fz_catch(ctx)
    {
        return NULL;
    }

    return list;
}

static fz_display_list *create_annot_list(fz_document *doc, fz_page *page)
{
    fz_display_list *list = NULL;
    fz_device *dev = NULL;

    fz_var(dev);
    fz_try(ctx)
    {
        fz_annot *annot;
        pdf_document *idoc = pdf_specifics(ctx, doc);

        if (idoc)
            pdf_update_page(ctx, (pdf_page *)page);
        list = fz_new_display_list(ctx, NULL);
        dev = fz_new_list_device(ctx, list);
        for (annot = fz_first_annot(ctx, page); annot; annot = fz_next_annot(ctx, annot))
            fz_run_annot(ctx, annot, dev, &fz_identity, NULL);
        fz_close_device(ctx, dev);
    }
    fz_always(ctx)
    {
        fz_drop_device(ctx, dev);
    }
    fz_catch(ctx)
    {
        return NULL;
    }

    return list;
}

static fz_pixmap *renderPixmap(fz_document *doc, fz_display_list *page_list, fz_display_list *annot_list, CGSize pageSize, CGSize screenSize, CGRect tileRect, float zoom)
{
    fz_irect bbox;
    fz_rect rect;
    fz_matrix ctm;
    fz_device *dev = NULL;
    fz_pixmap *pix = NULL;
    CGSize scale;

    screenSize.width *= screenScale;
    screenSize.height *= screenScale;
    tileRect.origin.x *= screenScale;
    tileRect.origin.y *= screenScale;
    tileRect.size.width *= screenScale;
    tileRect.size.height *= screenScale;

    scale = fitPageToScreen(pageSize, screenSize);
    fz_scale(&ctm, scale.width * zoom, scale.height * zoom);

    bbox.x0 = tileRect.origin.x;
    bbox.y0 = tileRect.origin.y;
    bbox.x1 = tileRect.origin.x + tileRect.size.width;
    bbox.y1 = tileRect.origin.y + tileRect.size.height;
    fz_rect_from_irect(&rect, &bbox);

    fz_var(dev);
    fz_var(pix);
    fz_try(ctx)
    {
        pix = fz_new_pixmap_with_bbox(ctx, fz_device_rgb(ctx), &bbox, 1);
        fz_clear_pixmap_with_value(ctx, pix, 255);

        dev = fz_new_draw_device(ctx, NULL, pix);
        fz_run_display_list(ctx, page_list, dev, &ctm, &rect, NULL);
        fz_run_display_list(ctx, annot_list, dev, &ctm, &rect, NULL);

        fz_close_device(ctx, dev);
    }
    fz_always(ctx)
    {
        fz_drop_device(ctx, dev);
    }
    fz_catch(ctx)
    {
        fz_drop_pixmap(ctx, pix);
        return NULL;
    }

    return pix;
}

@interface DYPDFView () <UIScrollViewDelegate>

@property(nonatomic, assign) int pageIdx;
@property(nonatomic, assign) BOOL cancel;

@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, strong) NSArray *widgetRects;
@property(nonatomic, strong) NSArray *annotations;
@property(nonatomic, strong) MuDocRef *docRef;
@property(nonatomic, strong) UIActivityIndicatorView *loadingView;

@end

@implementation DYPDFView {
    fz_page *page;
    fz_display_list *page_list;
    fz_display_list *annot_list;
    fz_pixmap *image_pix;
    CGDataProviderRef imageData;
    CGSize pageSize;
}

- (instancetype)initWithPage:(int)pageIdx
                         doc:(MuDocRef *)docRef {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.bouncesZoom = NO;
        self.showsVerticalScrollIndicator = NO;
        self.showsHorizontalScrollIndicator = NO;
        self.delegate = self;
        
        [self resetZoomAnimated:NO];
        self.docRef = docRef;
        self.pageIdx = pageIdx;
        self.docRef = docRef;
        self.backgroundColor = UIColor.clearColor;
        [self loadPage];
    }
    return self;
}

- (void)resetZoomAnimated: (BOOL)animated {
    self.minimumZoomScale = 1;
    self.maximumZoomScale = 5;
    [self setZoomScale:1 animated:animated];
}

- (void) removeFromSuperview
{
    self.cancel = YES;
    [super removeFromSuperview];
}

- (void) loadAnnotations
{
    if (self.pageIdx < 0 || self.pageIdx >= fz_count_pages(ctx, self.docRef->doc))
        return;

    NSArray *annots = enumerateAnnotations(self.docRef->doc, page);
    dispatch_async(dispatch_get_main_queue(), ^{
        self.annotations = annots;
    });
}

- (void) loadPage
{
    if (self.pageIdx < 0 || self.pageIdx >= fz_count_pages(ctx, self.docRef->doc))
        return;
    dispatch_async(queue, ^{
        if (!self.cancel) {
            [self renderPage];
        } else {
            printf("cancel page %d\n", self.pageIdx);
        }
    });
}

- (void) renderPage
{
    printf("render page %d\n", self.pageIdx);
    [self ensureDisplaylists];
    CGSize scale = fitPageToScreen(pageSize, self.bounds.size);
    // 按照pageSize生成图片
    scale = CGSizeMake(1, 1);
    CGRect rect = (CGRect){{0.0, 0.0},{pageSize.width * scale.width, pageSize.height * scale.height}};
    image_pix = renderPixmap(self.docRef->doc, page_list, annot_list, pageSize, pageSize, rect, 1.0);
    if (!image_pix) {
        return;
    }
    CGDataProviderRelease(imageData);
    imageData = CreateWrappedPixmap(image_pix);
    UIImage *image = newImageWithPixmap(image_pix, imageData);
    self.widgetRects = enumerateWidgetRects(self.docRef->doc, page);
    [self loadAnnotations];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self displayImage: image];
        [self.imageView setNeedsDisplay];
    });
}

- (void) displayImage: (UIImage*)image
{
    if (self.loadingView) {
        [self.loadingView removeFromSuperview];
        self.loadingView = nil;
    }

    if (!self.imageView) {
        self.imageView = [[UIImageView alloc] initWithImage: image];
        self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
        self.imageView.opaque = YES;
        self.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview: self.imageView];
    } else {
        self.imageView.image = image;
    }
    
}

- (void) resizeImage
{
    if (self.imageView) {
        CGSize imageSize =self.imageView.image.size;
        CGSize scale = fitPageToScreen(imageSize, self.bounds.size);
        if (fabs(scale.width - 1) > 0.1) {
            CGRect frame =self.imageView.frame;
            frame.size.width = imageSize.width * scale.width;
            frame.size.height = imageSize.height * scale.height;
           self.imageView.frame = frame;

            printf("resized view; queuing up a reload (%d)\n", self.pageIdx);
            dispatch_async(queue, ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    CGSize scale = fitPageToScreen(self.imageView.image.size, self.bounds.size);
                    if (fabs(scale.width - 1) > 0.01)
                        [self loadPage];
                });
            });
        } else {
            [self.imageView sizeToFit];
        }

        self.contentSize = self.imageView.frame.size;

        [self layoutIfNeeded];
    }

}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGSize boundsSize = self.bounds.size;
    CGRect frameToCenter = self.imageView.frame;
    
    if (frameToCenter.size.width < boundsSize.width) {
        frameToCenter.origin.x = floor((boundsSize.width - frameToCenter.size.width) / 2);
    } else {
        frameToCenter.origin.x = 0;
    }
    
    if (frameToCenter.size.height < boundsSize.height) {
        frameToCenter.origin.y = floor((boundsSize.height - frameToCenter.size.height) / 2);
    } else {
        frameToCenter.origin.y = 0;
    }
    
    self.imageView.frame = frameToCenter;
}

- (void) ensurePageLoaded
{
    if (page)
        return;

    fz_try(ctx)
    {
        fz_rect bounds;
        page = fz_load_page(ctx, self.docRef->doc, self.pageIdx);
        fz_bound_page(ctx, page, &bounds);
        pageSize.width = bounds.x1 - bounds.x0;
        pageSize.height = bounds.y1 - bounds.y0;
    }
    fz_catch(ctx)
    {
        return;
    }
}

- (void) ensureDisplaylists
{
    [self ensurePageLoaded];
    if (!page)
        return;

    if (!page_list)
        page_list = create_page_list(self.docRef->doc, page);

    if (!annot_list)
        annot_list = create_annot_list(self.docRef->doc, page);
}

#pragma mark - UIScrollViewDelegate


//- (void)scrollViewDidScroll:(UIScrollView *)scrollView;
//- (void)scrollViewDidZoom:(UIScrollView *)scrollView;
//
//// called on start of dragging (may require some time and or distance to move)
//- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView;
//// called on finger up if the user dragged. velocity is in points/millisecond. targetContentOffset may be changed to adjust where the scroll view comes to rest
//- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset API_AVAILABLE(ios(5.0));
//// called on finger up if the user dragged. decelerate is true if it will continue moving afterwards
//- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate;
//
//- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView;   // called on finger up as we are moving
//- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;      // called when scroll view grinds to a halt
//
//- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView; // called when setContentOffset/scrollRectVisible:animated: finishes. not called if not animating
//
- (nullable UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}
//- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(nullable UIView *)view API_AVAILABLE(ios(3.2)); // called before the scroll view begins zooming its content
//- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(nullable UIView *)view atScale:(CGFloat)scale; // scale between minimum and maximum. called after any 'bounce' animations
//
//- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView;   // return a yes if you want to scroll to the top. if not defined, assumes YES
//- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView;      // called when scrolling animation finished. may be called immediately if already at top
//
///* Also see -[UIScrollView adjustedContentInsetDidChange]
// */
//- (void)scrollViewDidChangeAdjustedContentInset:(UIScrollView *)scrollView API_AVAILABLE(ios(11.0), tvos(11.0));

@end
