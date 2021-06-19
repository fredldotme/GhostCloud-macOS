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

#include <QDebug>

#include "SharedStateOverview.h"

@implementation FileProviderEnumerator

- (instancetype)initWithItemIdentifier:(NSFileProviderItemIdentifier)containerItemIdentifier {
    self = [super init];
    self->itemIdentifier = containerItemIdentifier;
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
    NSMutableArray<FileProviderItem*>* items = [[NSMutableArray alloc] init];
    if ([self->itemIdentifier isEqualToString:NSFileProviderRootContainerItemIdentifier]) {
        QVector<AccountBase*> accounts = SharedStateOverview::Instance()->accounts();
        for (AccountBase* account : accounts) {
            QString namePattern = SharedStateOverview::Instance()->getIdentifierForAccount(account);
            FileProviderItem *item = [[FileProviderItem alloc] initWithName:namePattern.toNSString()
                                                     initWithItemIdentifier:namePattern.toNSString()
                                                                 withUTType:UTTypeFolder
                                                                 withParent:NSFileProviderRootContainerItemIdentifier
                                                                 withSize: 0];
            SharedStateOverview::Instance()->addFileProviderItem(QString::fromNSString(namePattern.toNSString()), item);
            [items addObject:item];
        }
    } else if (![self->itemIdentifier isEqualToString:NSFileProviderWorkingSetContainerItemIdentifier]) {
        qInfo() << "Enumerating items on" << self->itemIdentifier;
        QStringList pathCrumbs = QString::fromNSString(self->itemIdentifier).split("/", QString::SkipEmptyParts);
        QString providerIdentifier = "";
        if (pathCrumbs.length() > 0)
            providerIdentifier = pathCrumbs.takeFirst();
        
        QString remotePath = "/";
        if (pathCrumbs.length() > 0)
            remotePath = "/" + pathCrumbs.join("/") + "/";
        
        if (providerIdentifier.isEmpty()) {
            qWarning() << "providerIdentifier is empty!" << self->itemIdentifier;
            goto done;
        }

        AccountWorkers* desiredWorkers = nullptr;
        for (AccountWorkers* potentialWorkers : SharedStateOverview::Instance()->workers()) {
            if (providerIdentifier == SharedStateOverview::Instance()->getIdentifierForAccount(potentialWorkers->account())) {
                desiredWorkers = potentialWorkers;
                break;
            }
        }

        if (!desiredWorkers)
            goto done;
        
        CloudStorageProvider* commandQueue = desiredWorkers->browserCommandQueue();
        CommandEntity* command = commandQueue->directoryListingRequest(remotePath, false, false);
        AccountBase* desiredAccount = nullptr;
        
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

            QString idPath = QString::fromNSString(self->itemIdentifier) + "/" + name;
            if (isDir)
                idPath += "/";
            
            qDebug() << "IDPATH:" << idPath;
            FileProviderItem *item = [[FileProviderItem alloc] initWithName:name.toNSString()
                                                     initWithItemIdentifier:idPath.toNSString()
                                                                 withUTType: isDir ? UTTypeFolder : UTTypePlainText
                                                                 withParent: self->itemIdentifier
                                                                 withSize: isDir ? 0 : size];
            SharedStateOverview::Instance()->addFileProviderItem(idPath, item);
            [items addObject:item];
        }
    }

done:
    [observer didEnumerateItems:items];
    [observer finishEnumeratingUpToPage:nil];
}

@end
