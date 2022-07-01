//
//  DYChapter.h
//  DYReader
//
//  Created by oneko on 2022/6/30.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYChapter : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) int pageIdx;

+ (instancetype)chapterWithTitle:(NSString *)title page:(int)pageIdx;

@end

NS_ASSUME_NONNULL_END
