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

@interface DYPDFView ()

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

- (instancetype)initWithFrame:(CGRect)frame
                         page:(int)pageIdx
                          doc:(MuDocRef *)docRef {
    self = [super initWithFrame:frame];
    if (self) {
        self.docRef = docRef;
        self.pageIdx = pageIdx;
        self.docRef = docRef;
        [self loadPage];
    }
    return self;
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
    CGRect rect = (CGRect){{0.0, 0.0},{pageSize.width * scale.width, pageSize.height * scale.height}};
    image_pix = renderPixmap(self.docRef->doc, page_list, annot_list, pageSize, self.bounds.size, rect, 1.0);
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

    UIImageView *imageView = self.imageView;
    NSDictionary *views = NSDictionaryOfVariableBindings(imageView);
    NSArray *hConstratins = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[imageView]-|" options:0 metrics:nil views:views];
    NSArray *vConstratins = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[imageView]-|" options:0 metrics:nil views:views];
    [self addConstraints:hConstratins];
    [self addConstraints:vConstratins];
    
    [self layoutIfNeeded];
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

//        self.contentSize = self.imageView.frame.size;

        [self layoutIfNeeded];
    }

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

@end
