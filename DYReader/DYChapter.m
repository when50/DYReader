//
//  DYChapter.m
//  DYReader
//
//  Created by oneko on 2022/6/30.
//

#import "DYChapter.h"

@implementation DYChapter

+ (instancetype)chapterWithTitle:(NSString *)title page:(int)pageIdx {
    DYChapter *chapter = [DYChapter new];
    chapter.title = title;
    chapter.pageIdx = pageIdx;
    return chapter;
}

@end
