//
//  FileProviderItem.m
//  FileProvider
//
//  Created by Alfred Neumayer on 17.06.21.
//

#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "FileProviderItem.h"

@implementation FileProviderItem

@synthesize filename = _filename;
@synthesize itemIdentifier = _itemIdentifier;
@synthesize parentItemIdentifier = _parentItemIdentifier;
@synthesize itemVersion = _itemVersion;
@synthesize contentType = _contentType;
@synthesize documentSize = _documentSize;

- (instancetype)initWithName:(NSString*)name
                initWithItemIdentifier:(NSFileProviderItemIdentifier)identifier
                withUTType:(UTType *)utType
                withParent:(NSFileProviderItemIdentifier)parent
                withSize:(unsigned long long)size
{
    self = [super init];
    if (self == nil)
        goto done;

    _filename = [name copy];
    _itemIdentifier = [identifier copy];
    _parentItemIdentifier = parent;
    _itemVersion = [[NSFileProviderItemVersion alloc] initWithContentVersion:[@"a content version" dataUsingEncoding:NSUTF8StringEncoding] metadataVersion:[@"a metadata version" dataUsingEncoding:NSUTF8StringEncoding]];
    _contentType = utType;
    _documentSize = [[NSNumber alloc] initWithLongLong:size];

done:
    return self;
}

@end
