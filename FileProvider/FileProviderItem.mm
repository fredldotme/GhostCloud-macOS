//
//  FileProviderItem.m
//  FileProvider
//
//  Created by Alfred Neumayer on 17.06.21.
//

#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "FileProviderItem.h"
#include <util/filepathutil.h>
#include "SharedStateOverview.h"

@implementation FileProviderItem

@synthesize filename = _filename;
@synthesize itemIdentifier = _itemIdentifier;
@synthesize parentItemIdentifier = _parentItemIdentifier;
@synthesize itemVersion = _itemVersion;
@synthesize contentType = _contentType;
@synthesize documentSize = _documentSize;
@synthesize creationDate = _creationDate;
@synthesize contentModificationDate = _contentModificationDate;
@synthesize downloading = _downloading;
@synthesize downloaded = _downloaded;
@synthesize mostRecentVersionDownloaded = _mostRecentVersionDownloaded;

- (instancetype)initWithName:(NSString*)name
                initWithItemIdentifier:(NSFileProviderItemIdentifier)identifier
                withUTType:(UTType *)utType
                withParent:(NSFileProviderItemIdentifier)parent
                withSize:(unsigned long long)size
                withVersion:(NSString*)version
                withCreationDate:(NSDate*)creationDate
                withModificationDate:(NSDate*)modificationDate
{
    self = [super init];
    if (self == nil)
        goto done;

    _filename = [name copy];
    _itemIdentifier = [identifier copy];
    _parentItemIdentifier = parent;
    _itemVersion = [[NSFileProviderItemVersion alloc] initWithContentVersion:[version dataUsingEncoding:NSUTF8StringEncoding] metadataVersion:[version dataUsingEncoding:NSUTF8StringEncoding]];
    _contentType = utType;
    _documentSize = [[NSNumber alloc] initWithLongLong:size];
    _creationDate = creationDate;
    _contentModificationDate = modificationDate;

done:
    return self;
}

- (void)setIsDownloading:(BOOL)value
{
    _downloading = value;
}

- (void)setIsDownloaded:(BOOL)value
{
    _downloaded = value;
}

- (void)setIsMostRecentDownloaded:(BOOL)value
{
    _mostRecentVersionDownloaded = value;
}
@end
