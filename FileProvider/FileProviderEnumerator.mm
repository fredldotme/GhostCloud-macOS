//
//  FileProviderEnumerator.m
//  FileProvider
//
//  Created by Alfred Neumayer on 17.06.21.
//

#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "FileProviderEnumerator.h"
#import "FileProviderItem.h"
#import "FileProviderHelpers.h"

#include <QDebug>
#include <QCryptographicHash>

#include "SharedStateOverview.h"

@implementation FileProviderEnumerator

- (instancetype)initWithItemIdentifier:(NSFileProviderItemIdentifier)containerItemIdentifier withAnchor:(NSInteger)currentAnchor {
    self = [super init];
    self->itemIdentifier = containerItemIdentifier;
    self->currentAnchor = currentAnchor;
    qDebug() << "ITEMIDENTIFIER:" << containerItemIdentifier;
    return self;
}

- (void)invalidate {
    // TODO: perform invalidation of server connection if necessary
}

- (void)enumerateItemsForObserver:(nonnull id<NSFileProviderEnumerationObserver>)observer startingAtPage:(nonnull NSFileProviderPage)page {
    /* TODO:
     - inspect the page to determine whether this is an initial or a follow-up request
     
     If this is an enumerator for a directory, the root container or all directories:
     - perform a server request to fetch directory contents
     If this is an enumerator for the active set:
     - perform a server request to update your local database
     - fetch the active set from your local database
     
     - inform the observer about the items returned by the server (possibly multiple times)
     - inform the observer that you are finished with this page
     */

    qDebug() << Q_FUNC_INFO << itemIdentifier;
    std::function<void()> operation = [=]() {
        qDebug() << Q_FUNC_INFO << self->itemIdentifier;
        NSMutableArray<FileProviderItem*>* items = [[NSMutableArray alloc] init];

        if ([self->itemIdentifier isEqualToString:NSFileProviderRootContainerItemIdentifier]) {
            QVector<AccountBase*> accounts = SharedStateOverview::Instance()->accounts();

            // Create version hash for the root directory first, who knows what happens...
            QString concatenatedAccountNames;
            for (AccountBase* account : accounts) {
                concatenatedAccountNames += getIdentifierForAccount(account);
            }

            QCryptographicHash hasher(QCryptographicHash::Sha256);
            hasher.addData(concatenatedAccountNames.toUtf8());
            NSString* versionHash = QString::fromUtf8(hasher.result()).toNSString();

            for (AccountBase* account : accounts) {
                QString namePattern = getIdentifierForAccount(account);
                FileProviderItem *item = [[FileProviderItem alloc] initWithName:namePattern.toNSString()
                                                                   initWithItemIdentifier:namePattern.toNSString()
                                                                   withUTType:UTTypeFolder
                                                                   withParent:NSFileProviderRootContainerItemIdentifier
                                                                   withSize: 0
                                                                   withVersion:versionHash
                                                                   withCreationDate:[NSDate date]
                                                                   withModificationDate:[NSDate date]];
                [item setIsDownloaded:TRUE];
                [item setIsDownloading:FALSE];
                [item setIsMostRecentDownloaded:TRUE];
                SharedStateOverview::Instance()->addFileProviderItem(QString::fromNSString(namePattern.toNSString()), item);
                [items addObject:item];
                qDebug() << "Added account dir" << account->hostname();
            }
        } else if (![self->itemIdentifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier] &&
                   ![self->itemIdentifier isEqualToString:NSFileProviderTrashContainerItemIdentifier]) {
            qInfo() << "Enumerating items on" << self->itemIdentifier;
#if QT_VERSION < 0x060000
            QStringList pathCrumbs = QString::fromNSString(self->itemIdentifier).split("/", QString::SkipEmptyParts);
#else
            QStringList pathCrumbs = QString::fromNSString(self->itemIdentifier).split("/", Qt::SkipEmptyParts);
#endif
            QString providerIdentifier = "";
            if (pathCrumbs.length() > 0)
                providerIdentifier = pathCrumbs.takeFirst();
            
            QString remotePath = "/";
            if (pathCrumbs.length() > 0)
                remotePath = "/" + pathCrumbs.join("/") + "/";
            
            if (providerIdentifier.isEmpty()) {
                qWarning() << "providerIdentifier is empty!" << self->itemIdentifier;
                [observer didEnumerateItems:items];
                [observer finishEnumeratingUpToPage:nil];
            }

            AccountWorkers* desiredWorkers = nullptr;
            for (AccountWorkers* potentialWorkers : SharedStateOverview::Instance()->workers()) {
                if (providerIdentifier == getIdentifierForAccount(potentialWorkers->account())) {
                    desiredWorkers = potentialWorkers;
                    break;
                }
            }

            if (!desiredWorkers) {
                qWarning() << "Didn't find workers for" << self->itemIdentifier;
                [observer didEnumerateItems:items];
                [observer finishEnumeratingUpToPage:nil];
            }
            
            CloudStorageProvider* commandQueue = desiredWorkers->browserCommandQueue();
            CommandEntity* command = commandQueue->directoryListingRequest(remotePath, false, false);

            command->run();
            command->waitForFinished();

            QVariantMap result = command->resultData();
            QVariantList contents = result.value("dirContent").toList();
            for (QVariant content : contents) {
                QVariantMap dirContent = content.toMap();
                const bool isDir = dirContent.value("isDirectory").toBool();
                const QString name = dirContent.value("name").toString();
                const QString path = dirContent.value("path").toString();
                const unsigned long long size = dirContent.value("size").toULongLong();
                // Argument against using uniqueId as version:
                // We can't upload the file with a new uniqueId string attached
                // as that is dictated by the server, so use the modification date instead.
                // const QString version = dirContent.value("uniqueId").toString();
                const QDateTime creationDate = dirContent.value("createdAt").toDateTime();
                const QDateTime modificationDate = dirContent.value("lastModification").toDateTime();
                const QString fileVersion = modificationDate.toString();

                QString idPath = QString::fromNSString(self->itemIdentifier);
                if (!idPath.endsWith("/"))
                    idPath += "/";
                idPath += name;
                if (isDir)
                    idPath += "/";

                qDebug() << "IDPATH:" << idPath;
                FileProviderItem *item = [[FileProviderItem alloc] initWithName:name.toNSString()
                                                                   initWithItemIdentifier:idPath.toNSString()
                                                                   withUTType: isDir ? UTTypeFolder : UTTypePlainText
                                                                   withParent: self->itemIdentifier
                                                                   withSize: isDir ? 0 : size
                                                                   withVersion:fileVersion.toNSString()
                                                                   withCreationDate:creationDate.toNSDate()
                                                                   withModificationDate:modificationDate.toNSDate()];
                const QString localPath = FilePathUtil::destination(desiredWorkers->account()) + remotePath;
                const bool exists = FilePathUtil::fileExists(localPath);
                [item setIsDownloaded:exists];
                [item setIsDownloading:FALSE];
                [item setIsMostRecentDownloaded:exists && fileVersion == QFileInfo(localPath).lastModified().toString()];
                SharedStateOverview::Instance()->addFileProviderItem(idPath, item);
                [items addObject:item];
            }
        }

        [observer didEnumerateItems:items];
        [observer finishEnumeratingUpToPage:nil];
    };

    runDefaultConnectedOperation(operation);
}

/*
- (void)enumerateChangesForObserver:(id<NSFileProviderChangeObserver>)observer
                     fromSyncAnchor:(NSFileProviderSyncAnchor)syncAnchor
{
    
}
*/

/*- (void)currentSyncAnchorWithCompletionHandler:(void(^)(_Nullable NSFileProviderSyncAnchor currentAnchor))completionHandler
{
    NSData* anchor = [[NSString stringWithFormat:@"%ld",(long)self->currentAnchor] dataUsingEncoding:NSUTF8StringEncoding];
    completionHandler(anchor);
}*/

@end
