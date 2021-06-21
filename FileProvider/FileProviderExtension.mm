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
#import "FileProviderHelpers.h"

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
    self->anchor = 0;
    return self;
}

- (void)invalidate {
    self->anchor = 0;
}

- (nullable id<NSFileProviderEnumerator>)enumeratorForContainerItemIdentifier:(nonnull NSFileProviderItemIdentifier)containerItemIdentifier request:(nonnull NSFileProviderRequest *)request error:(NSError *__autoreleasing  _Nullable * _Nullable)error {
    FileProviderEnumerator* enumerator = [[FileProviderEnumerator alloc] initWithItemIdentifier: containerItemIdentifier withAnchor:self->anchor++];
    return enumerator;
}

- (nonnull NSProgress *)createItemBasedOnTemplate:(nonnull NSFileProviderItem)itemTemplate fields:(NSFileProviderItemFields)fields contents:(nullable NSURL *)url options:(NSFileProviderCreateItemOptions)options request:(nonnull NSFileProviderRequest *)request completionHandler:(nonnull void (^)(NSFileProviderItem _Nullable, NSFileProviderItemFields, BOOL, NSError * _Nullable))completionHandler {
    qDebug() << Q_FUNC_INFO << itemTemplate.itemIdentifier << fields << url << options;

    NSProgress* progressIndicator = [[NSProgress alloc] init];
    NSFileProviderManager* manager = SharedStateOverview::Instance()->providerManager();

    // Prepare lambda
    std::function<void(NSURL*, NSString*, bool)> actualCreation = [=](NSURL *userVisibleFile, NSString* identifier, bool isDir) {
        BOOL lockSuccess = [userVisibleFile startAccessingSecurityScopedResource];

        const QFileInfo fileInfo(QUrl::fromNSURL(userVisibleFile).toLocalFile());

        FileProviderItem *item = [[FileProviderItem alloc] initWithName:itemTemplate.filename
                                                           initWithItemIdentifier:identifier
                                                           withUTType: isDir ? UTTypeFolder : UTTypePlainText
                                                           withParent:itemTemplate.parentItemIdentifier
                                                           withSize: isDir ? 0 : fileInfo.size()
                                                           withVersion: fileInfo.lastModified().toString().toNSString()
                                                           withCreationDate:fileInfo.birthTime().toNSDate()
                                                           withModificationDate:fileInfo.lastModified().toNSDate()];
        [item setIsDownloaded:TRUE];
        [item setIsDownloading:FALSE];
        [item setIsMostRecentDownloaded:TRUE];
        QString ident = QString::fromNSString(identifier);
        SharedStateOverview::Instance()->addFileProviderItem(ident, item);
        QString localPath = QUrl::fromNSURL(userVisibleFile).toLocalFile();
        QFileInfo localFileInfo(localPath);

        const bool isLocalFileInfoDir = localFileInfo.isDir();
        const bool isLocalFileInfoFile = localFileInfo.isFile();

        if (lockSuccess)
            [userVisibleFile stopAccessingSecurityScopedResource];

        if (isLocalFileInfoDir) {
            QString remotePath = findRemoteDirForIdentifier(ident) + QString::fromNSString(itemTemplate.filename);
            std::function<void()> successHandler = [=]() {
                NSFileProviderItemFields remainingFields = 0;
                completionHandler(item, remainingFields, false, nil);
                [SharedStateOverview::Instance()->providerManager() signalEnumeratorForContainerItemIdentifier:item.parentItemIdentifier completionHandler:^(NSError * _Nullable error) {
                    qDebug() << "Directory contents after directory creation refreshed";
                }];
            };
            std::function<void()> failHandler = [=]() {
                NSFileProviderItemFields remainingFields = fields;
                NSError* error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
                completionHandler(item, remainingFields, false, error);
            };
            runDefaultConnectedOperation([=](){
                SharedStateOverview::Instance()->causeDirectoryCreation(ident,
                                                                        remotePath,
                                                                        successHandler,
                                                                        failHandler);
            });
        } else if (isLocalFileInfoFile) {
            std::function<void()> successHandler = [=]() {
                NSFileProviderItemFields remainingFields = 0;
                completionHandler(item, remainingFields, false, nil);
                [SharedStateOverview::Instance()->providerManager() signalEnumeratorForContainerItemIdentifier:item.parentItemIdentifier completionHandler:^(NSError * _Nullable error) {
                    qDebug() << "Directory contents after file upload refreshed";
                }];
            };
            std::function<void()> failHandler = [=]() {
                NSFileProviderItemFields remainingFields = fields;
                NSError* error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
                completionHandler(item, remainingFields, false, error);
            };

            runDefaultConnectedOperation([=](){
                FileProviderItem* item = SharedStateOverview::Instance()->getFileProviderItem(ident);
                SharedStateOverview::Instance()->causeUpload(item,
                                                             userVisibleFile,
                                                             progressIndicator,
                                                             successHandler,
                                                             failHandler,
                                                             url,
                                                             QString::fromNSString(itemTemplate.filename));
            });
        }
    };

    // Lambda is prepared, start actual work
    [manager getUserVisibleURLForItemIdentifier:itemTemplate.itemIdentifier
                              completionHandler:[=](NSURL *userVisibleFile, NSError *error) {
        qDebug() << Q_FUNC_INFO << userVisibleFile << error;
        if (error != nil) {
            qWarning() << Q_FUNC_INFO << "Error:" << error;
            NSFileProviderItemFields remainingFields = 0;
            completionHandler(itemTemplate, remainingFields, false, nil);
            return;
        }

        FileProviderItem* parentItem = SharedStateOverview::Instance()->getFileProviderItem(QString::fromNSString(itemTemplate.parentItemIdentifier));
        qDebug() << Q_FUNC_INFO << parentItem << itemTemplate.parentItemIdentifier;

        const bool isDir = (itemTemplate.contentType == UTTypeFolder);
        NSFileProviderItemIdentifier newIdentifier = getNewIdentifierForTemplateCreation(itemTemplate.parentItemIdentifier,
                                                                                         itemTemplate.filename,
                                                                                         isDir);
        qDebug() << Q_FUNC_INFO << "newIdentifier" << newIdentifier;

        /*if (parentItem == nil) {
            // Fetch new directory listing and upload afterwards.
            [SharedStateOverview::Instance()->providerManager() signalEnumeratorForContainerItemIdentifier:parentItem.itemIdentifier completionHandler:^(NSError * _Nullable error) {
                qDebug() << "ERROR:" << error << parentItem.itemIdentifier;
                runDefaultConnectedOperation([=](){
                    actualCreation(userVisibleFile, newIdentifier, isDir);
                });
            }];
            return;
        }*/

        runDefaultConnectedOperation([=](){
            actualCreation(userVisibleFile, newIdentifier, isDir);
        });
        return;
    }];
    return progressIndicator;
}

- (nonnull NSProgress *)deleteItemWithIdentifier:(nonnull NSFileProviderItemIdentifier)identifier baseVersion:(nonnull NSFileProviderItemVersion *)version options:(NSFileProviderDeleteItemOptions)options request:(nonnull NSFileProviderRequest *)request completionHandler:(nonnull void (^)(NSError * _Nullable))completionHandler {
    NSProgress* progressIndicator = [[NSProgress alloc] init];

    std::function<void()> deleteOperation = [=](){
        std::function<void()> compHandler = [=](){
            NSError* error = nil;
            completionHandler(error);
        };
        
        std::function<void()> failureHandler = [=](){
            NSError* error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
            completionHandler(error);
        };
        
        SharedStateOverview::Instance()->causeDelete(QString::fromNSString(identifier),
                                                     compHandler,
                                                     failureHandler);
    };
    runDefaultConnectedOperation(deleteOperation);
    
    return progressIndicator;
}

- (nonnull NSProgress *)fetchContentsForItemWithIdentifier:(nonnull NSFileProviderItemIdentifier)itemIdentifier version:(nullable NSFileProviderItemVersion *)requestedVersion request:(nonnull NSFileProviderRequest *)request completionHandler:(nonnull void (^)(NSURL * _Nullable, NSFileProviderItem _Nullable, NSError * _Nullable))completionHandler {
    NSProgress* progressIndicator = [[NSProgress alloc] init];
    qDebug() << Q_FUNC_INFO << itemIdentifier << requestedVersion.contentVersion;
    
    QString ident = QString::fromNSString(itemIdentifier);
    FileProviderItem* item = SharedStateOverview::Instance()->getFileProviderItem(ident);
    if (item != nil) {
        [item setIsDownloading:TRUE];
    }
    std::function<void()> downloadOperation = [=](){
        std::function<void(QString)> compHandler = [=](QString localPath){
            FileProviderItem* item = SharedStateOverview::Instance()->getFileProviderItem(ident);
            NSError* error = nil;
            qDebug() << Q_FUNC_INFO << item << error << localPath << "calling completinoHandler";
            [item setIsDownloaded:TRUE];
            [item setIsDownloading:FALSE];
            [item setIsMostRecentDownloaded:TRUE];

            NSURL* url = QUrl::fromLocalFile(localPath).toNSURL();
            const BOOL lockSuccess = [url startAccessingSecurityScopedResource];
            completionHandler(QUrl::fromLocalFile(localPath).toNSURL(), item, error);
            if (lockSuccess)
                [url stopAccessingSecurityScopedResource];
        };
        
        std::function<void(QString)> failureHandler = [=](QString localPath){
            FileProviderItem* item = SharedStateOverview::Instance()->getFileProviderItem(QString::fromNSString(itemIdentifier));
            [item setIsDownloaded:FALSE];
            [item setIsDownloading:FALSE];
            [item setIsMostRecentDownloaded:FALSE];
            NSError* error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
            qDebug() << Q_FUNC_INFO << item << error << localPath << "calling completinoHandler";
            completionHandler(QUrl::fromLocalFile(localPath).toNSURL(), item, error);
        };

        SharedStateOverview::Instance()->causeDownload(QString::fromNSString(itemIdentifier),
                                                       progressIndicator,
                                                       compHandler,
                                                       failureHandler);
    };
    //downloadOperation();
    runDefaultConnectedOperation(downloadOperation);

    return progressIndicator;
}

- (nonnull NSProgress *)itemForIdentifier:(nonnull NSFileProviderItemIdentifier)identifier request:(nonnull NSFileProviderRequest *)request completionHandler:(nonnull void (^)(NSFileProviderItem _Nullable, NSError * _Nullable))completionHandler {
    // resolve the given identifier to a record in the model
    qDebug() << Q_FUNC_INFO << identifier;

    std::function<void()> getItemOperation = [=](){
        if ([identifier isEqualToString:NSFileProviderRootContainerItemIdentifier]) {
            FileProviderItem* item = SharedStateOverview::Instance()->getRootItem();
            if (item) {
                completionHandler(item, nil);
                return;
            }

            [SharedStateOverview::Instance()->providerManager() signalEnumeratorForContainerItemIdentifier:identifier completionHandler:^(NSError * _Nullable error) {
                qDebug() << "ERROR:" << error << identifier;
                QString ident = QString::fromNSString(identifier);
                FileProviderItem* item = SharedStateOverview::Instance()->getFileProviderItem(ident);
                completionHandler(item, error);
            }];
        } else if (![identifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier] &&
                   ![identifier isEqualToString:NSFileProviderTrashContainerItemIdentifier]){
            QString ident = QString::fromNSString(identifier);
            FileProviderItem* item = SharedStateOverview::Instance()->getFileProviderItem(ident);
            if (!item) {
                [SharedStateOverview::Instance()->providerManager() signalEnumeratorForContainerItemIdentifier:identifier completionHandler:^(NSError * _Nullable error) {
                    qDebug() << "ERROR:" << error << identifier;
                    FileProviderItem* item = SharedStateOverview::Instance()->getFileProviderItem(ident);
                    completionHandler(item, error);
                }];
                return;
            }
            completionHandler(item, nil);
        } else {
            NSError* error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError userInfo:nil];
            completionHandler(nil, error);
        }
    };
    runDefaultConnectedOperation(getItemOperation);
    return [[NSProgress alloc] init];
}

- (nonnull NSProgress *)modifyItem:(nonnull NSFileProviderItem)item baseVersion:(nonnull NSFileProviderItemVersion *)version changedFields:(NSFileProviderItemFields)changedFields contents:(nullable NSURL *)newContents options:(NSFileProviderModifyItemOptions)options request:(nonnull NSFileProviderRequest *)request completionHandler:(nonnull void (^)(NSFileProviderItem _Nullable, NSFileProviderItemFields, BOOL, NSError * _Nullable))completionHandler
{
    NSFileProviderItemFields remainingFields = 0;
    
    const QString identifier = QString::fromNSString(item.itemIdentifier);

    qDebug() << Q_FUNC_INFO << newContents << identifier;
    
    // Avoid uploading directories
    if (identifier.endsWith("/"))
        return nil;

    // If the identifier is a root-level account directory => skip as well
    for (AccountBase* account : SharedStateOverview::Instance()->accounts()) {
        if (identifier == getIdentifierForAccount(account))
            return nil;
    }

    NSProgress* progressIndicator = [[NSProgress alloc] init];
    FileProviderItem* fpItem = SharedStateOverview::Instance()->getFileProviderItem(identifier);
    if (fpItem != nil) {
        [fpItem setIsMostRecentDownloaded:FALSE];
    }

    std::function<void()> upOperation = [=](){
        std::function<void()> compHandler = [=](){
            [SharedStateOverview::Instance()->providerManager() signalEnumeratorForContainerItemIdentifier:identifier.toNSString() completionHandler:^(NSError * _Nullable error) {
                qDebug() << "ERROR:" << error << identifier;
                FileProviderItem* item = SharedStateOverview::Instance()->getFileProviderItem(identifier);
                [item setIsMostRecentDownloaded:TRUE];
                completionHandler(item, remainingFields, false, error);
            }];
        };
        
        std::function<void()> failureHandler = [=](){
            NSError* error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
            completionHandler(item, remainingFields, false, error);
        };

        SharedStateOverview::Instance()->causeUpload(fpItem,
                                                     newContents,
                                                     progressIndicator,
                                                     compHandler,
                                                     failureHandler,
                                                     nil,
                                                     "");
    };
    runDefaultConnectedOperation(upOperation);
    
    return progressIndicator;
}

/*- (void)materializedItemsDidChangeWithCompletionHandler:(void (^)(void))completionHandler
 {
 qDebug() << Q_FUNC_INFO;
 completionHandler();
 }*/

@end
