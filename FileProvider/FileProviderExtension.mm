//
//  FileProviderExtension.m
//  FileProvider
//
//  Created by Alfred Neumayer on 17.06.21.
//

#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "FileProviderExtension.h"
#import "FileProviderEnumerator.h"
#import "FileProviderItem.h"

#include <thread>
#include <QtCore/qcoreapplication.h>
#include <QtCore/qobject.h>
#include <QtSql/QSqlError>

#include <sharedstatecontroller.h>
#include <accountworkergenerator.h>
#include <settings/db/accountdb.h>

@implementation FileProviderExtension

- (nonnull instancetype)initWithDomain:(nonnull NSFileProviderDomain *)domain {
    self = [super init];
    return self;
}

- (void)invalidate {
}

- (nullable id<NSFileProviderEnumerator>)enumeratorForContainerItemIdentifier:(nonnull NSFileProviderItemIdentifier)containerItemIdentifier request:(nonnull NSFileProviderRequest *)request error:(NSError *__autoreleasing  _Nullable * _Nullable)error {
    FileProviderEnumerator* enumerator = [[FileProviderEnumerator alloc] initWithItemIdentifier: containerItemIdentifier];
    return enumerator;
}

- (nonnull NSProgress *)createItemBasedOnTemplate:(nonnull NSFileProviderItem)itemTemplate fields:(NSFileProviderItemFields)fields contents:(nullable NSURL *)url options:(NSFileProviderCreateItemOptions)options request:(nonnull NSFileProviderRequest *)request completionHandler:(nonnull void (^)(NSFileProviderItem _Nullable, NSFileProviderItemFields, BOOL, NSError * _Nullable))completionHandler {
    // TODO: a new item was created on disk, process the item's creation

    NSFileProviderItemFields remainingFields = 0;
    completionHandler(itemTemplate, remainingFields, false, nil);
    return [[NSProgress alloc] init];
}

- (nonnull NSProgress *)deleteItemWithIdentifier:(nonnull NSFileProviderItemIdentifier)identifier baseVersion:(nonnull NSFileProviderItemVersion *)version options:(NSFileProviderDeleteItemOptions)options request:(nonnull NSFileProviderRequest *)request completionHandler:(nonnull void (^)(NSError * _Nullable))completionHandler {
    // TODO: an item was deleted on disk, process the item's deletion

    SharedStateOverview::Instance()->causeDelete(QString::fromNSString(identifier));

    NSError *error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError userInfo:nil];
    completionHandler(error);
    return [[NSProgress alloc] init];
}

- (nonnull NSProgress *)fetchContentsForItemWithIdentifier:(nonnull NSFileProviderItemIdentifier)itemIdentifier version:(nullable NSFileProviderItemVersion *)requestedVersion request:(nonnull NSFileProviderRequest *)request completionHandler:(nonnull void (^)(NSURL * _Nullable, NSFileProviderItem _Nullable, NSError * _Nullable))completionHandler {
    // TODO: implement fetching of the contents for the itemIdentifier at the specified version

    QString localPath;
    const bool success = SharedStateOverview::Instance()->causeDownload(QString::fromNSString(itemIdentifier), localPath);

    NSError *error = nil;
    if (!success) {
        error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
    }
    FileProviderItem* item = SharedStateOverview::Instance()->getFileProviderItem(QString::fromNSString(itemIdentifier));
    completionHandler(QUrl::fromLocalFile(localPath).toNSURL(), item, error);
    return [[NSProgress alloc] init];
}

- (nonnull NSProgress *)itemForIdentifier:(nonnull NSFileProviderItemIdentifier)identifier request:(nonnull NSFileProviderRequest *)request completionHandler:(nonnull void (^)(NSFileProviderItem _Nullable, NSError * _Nullable))completionHandler {
    // resolve the given identifier to a record in the model

    // TODO: implement the actual lookup

    qDebug() << Q_FUNC_INFO << identifier;
    FileProviderItem* item = nil;
    if ([identifier isEqualToString:NSFileProviderRootContainerItemIdentifier]) {
        item = SharedStateOverview::Instance()->getRootItem();
    } else if (![identifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier]){
        item = SharedStateOverview::Instance()->getFileProviderItem(QString::fromNSString(identifier));
    }
    completionHandler(item, nil);
    return [[NSProgress alloc] init];
}

- (nonnull NSProgress *)modifyItem:(nonnull NSFileProviderItem)item baseVersion:(nonnull NSFileProviderItemVersion *)version changedFields:(NSFileProviderItemFields)changedFields contents:(nullable NSURL *)newContents options:(NSFileProviderModifyItemOptions)options request:(nonnull NSFileProviderRequest *)request completionHandler:(nonnull void (^)(NSFileProviderItem _Nullable, NSFileProviderItemFields, BOOL, NSError * _Nullable))completionHandler {
    // TODO: an item was modified on disk, process the item's modification
    
    NSFileProviderItemFields remainingFields = 0;
    NSError *error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError userInfo:nil];
    completionHandler(nil, remainingFields, false, error);
    return [[NSProgress alloc] init];
}

@end
