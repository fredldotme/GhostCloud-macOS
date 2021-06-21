//
//  FileProviderItem.h
//  FileProvider
//
//  Created by Alfred Neumayer on 17.06.21.
//

#import <FileProvider/FileProvider.h>

@interface FileProviderItem : NSObject<NSFileProviderItem>

- (instancetype)initWithName:(NSString*)name
                initWithItemIdentifier:(NSFileProviderItemIdentifier)itemIdentifier
                withUTType:(UTType*)utType
                withParent:(NSFileProviderItemIdentifier)parent
                withSize:(unsigned long long)size
                withVersion:(NSString*)version
                withCreationDate:(NSDate*)creationDate
                withModificationDate:(NSDate*)modificationDate;

- (void)setIsDownloading:(BOOL)value;

- (void)setIsDownloaded:(BOOL)value;

- (void)setIsMostRecentDownloaded:(BOOL)value;
@end
