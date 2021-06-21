//
//  SharedStateOvrviewController.cpp
//  FileProvider
//
//  Created by Alfred Neumayer on 18.06.21.
//

#import <Foundation/Foundation.h>
#include <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <QDateTime>
#include <QFileInfo>

#include <commandqueue.h>
#include <util/filepathutil.h>

#include "SharedStateOverview.h"
#include "FileProviderHelpers.h"

static std::thread qtThread;

void qtLoop(SharedStateOverview* instance) {
    instance->InitQt();
}

void messageOutput(QtMsgType, const QMessageLogContext &, const QString &msg)
{
    NSLog(@"%s", msg.toUtf8().data());
}

SharedStateOverview* SharedStateOverview::s_instance = nullptr;
bool SharedStateOverview::qtInited = false;
QRecursiveMutex instanceMutex;

SharedStateOverview* SharedStateOverview::Instance()
{
    QMutexLocker locker(&instanceMutex);
    if (!s_instance) {
        s_instance = new SharedStateOverview();
        qtThread = std::thread(qtLoop, s_instance);
        while (!SharedStateOverview::qtInited)
            QThread::msleep(100);
    }
    return s_instance;
}

SharedStateOverview::SharedStateOverview()
{
}

void SharedStateOverview::InitQt()
{
    if (!QCoreApplication::instance()) {
        qInstallMessageHandler(messageOutput);
        NSString* frameworksPath = [[NSBundle mainBundle] privateFrameworksPath];
        const QString pluginPath = QString::fromNSString(frameworksPath) +
                                   QStringLiteral("/harbourowncloudcommon.framework/Versions/Current/PlugIns");

        QCoreApplication::addLibraryPath(pluginPath);
        //qputenv("QT_EVENT_DISPATCHER_CORE_FOUNDATION", "1");
        qRegisterMetaType<CommandReceipt>("CommandReceipt");

        int argc = 1;
        char* argv[] = {"FileProvider", nullptr};
        this->m_app = new QCoreApplication(argc, argv);

        const QString QHOSTCLOUD_APP_NAME = QStringLiteral("me.fredl.GhostCloud-macOS.FileProvider");
        this->m_app->setApplicationName(QHOSTCLOUD_APP_NAME);
    }

    this->m_accountDatabase = new AccountDb();
    this->m_accountDatabase->refresh();
    this->m_generator = new AccountWorkerGenerator();
    this->m_generator->setDatabase(this->m_accountDatabase);
    SharedStateOverview::qtInited = true;
    this->m_app->exec();
}

AccountWorkerGenerator* SharedStateOverview::generator()
{
    return this->m_generator;
}

QVector<AccountBase*> SharedStateOverview::accounts()
{
    return this->m_accountDatabase->accounts();
}

QVector<AccountWorkers*> SharedStateOverview::workers()
{
    return this->m_generator->accountWorkersVector();
}

AccountBase* SharedStateOverview::accountForIdentifier(QString identifier)
{
    for (AccountBase* account : this->accounts()) {
        if (getIdentifierForAccount(account) == identifier)
            return account;
    }
    return nullptr;
}

NSFileProviderManager* SharedStateOverview::providerManager()
{
    NSFileProviderDomain* domain = [[NSFileProviderDomain alloc]
                                    initWithIdentifier:@"me.fredl.GhostCloud-macOS.FileProvider"
                                    displayName:@"GhostCloud"] ;
    NSFileProviderManager* manager = [NSFileProviderManager managerForDomain:domain];
    return manager;
}

FileProviderItem* SharedStateOverview::getFileProviderItem(const QString& identifier, bool fetchNew)
{
    qDebug() << "Trying to find FPI for id" << identifier;
    FileProviderItem* ret = nil;
    if (this->m_fileProviderItemMap.contains(identifier)) {
        qDebug() << "Found FileProviderItem:" << identifier;
        ret = this->m_fileProviderItemMap.value(identifier);
    }
    return ret;
}

void SharedStateOverview::addFileProviderItem(QString identifier, FileProviderItem *item)
{
    this->m_fileProviderItemMap.insert(identifier, item);
}

FileProviderItem* SharedStateOverview::getRootItem()
{
    FileProviderItem* item = [[FileProviderItem alloc] initWithName:NSFileProviderRootContainerItemIdentifier
                                             initWithItemIdentifier:NSFileProviderRootContainerItemIdentifier
                                             withUTType:UTTypeFolder
                                             withParent:NSFileProviderRootContainerItemIdentifier
                                             withSize: 0
                                             withVersion:@"rootItemVersion"
                                             withCreationDate:[NSDate date]
                                             withModificationDate:[NSDate date]];
    return item;
}

AccountWorkers* SharedStateOverview::findWorkersForIdentifier(QString identifier)
{
    AccountWorkers* ret = nullptr;
#if QT_VERSION < 0x060000
    QStringList pathCrumbs = identifier.split("/", QString::SkipEmptyParts);
#else
    QStringList pathCrumbs = identifier.split("/", Qt::SkipEmptyParts);
#endif
    QString providerIdentifier = "";
    if (pathCrumbs.length() > 0)
        providerIdentifier = pathCrumbs.takeFirst();

    if (providerIdentifier.isEmpty()) {
        qWarning() << "providerIdentifier is empty!" << identifier;
        goto done;
    }

    for (AccountWorkers* potentialWorkers : SharedStateOverview::Instance()->workers()) {
        if (providerIdentifier == getIdentifierForAccount(potentialWorkers->account())) {
            ret = potentialWorkers;
            break;
        }
    }

done:
    return ret;
}

void SharedStateOverview::causeContentListing(QString identifier,
                                              NSMutableArray<FileProviderItem*>* items,
                                              std::function<void()> completionHandler,
                                              std::function<void()> failureHandler)
{
    NSString* itemIdentifier = identifier.toNSString();
    qInfo() << "Enumerating items on" << itemIdentifier;

#if QT_VERSION < 0x060000
    QStringList pathCrumbs = QString::fromNSString(itemIdentifier).split("/", QString::SkipEmptyParts);
#else
    QStringList pathCrumbs = QString::fromNSString(itemIdentifier).split("/", Qt::SkipEmptyParts);
#endif
    QString providerIdentifier = "";
    if (pathCrumbs.length() > 0)
        providerIdentifier = pathCrumbs.takeFirst();
    
    QString remotePath = "/";
    if (pathCrumbs.length() > 0)
        remotePath = "/" + pathCrumbs.join("/") + "/";
    
    if (providerIdentifier.isEmpty()) {
        qWarning() << "providerIdentifier is empty!" << itemIdentifier;
        failureHandler();
    }
    
    AccountWorkers* desiredWorkers = nullptr;
    for (AccountWorkers* potentialWorkers : SharedStateOverview::Instance()->workers()) {
        if (providerIdentifier == getIdentifierForAccount(potentialWorkers->account())) {
            desiredWorkers = potentialWorkers;
            break;
        }
    }
    
    if (!desiredWorkers) {
        qWarning() << "Didn't find workers for" << itemIdentifier;
        failureHandler();
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
        const QString version = dirContent.value("uniqueId").toString();
        const QDateTime creationDate = dirContent.value("createdAt").toDateTime();
        const QDateTime modificationDate = dirContent.value("lastModification").toDateTime();

        QString idPath = QString::fromNSString(itemIdentifier);
        if (!idPath.endsWith("/"))
            idPath += "/";
        idPath += name;
        if (isDir)
            idPath += "/";
        
        qDebug() << "IDPATH:" << idPath;
        FileProviderItem *item = [[FileProviderItem alloc] initWithName:name.toNSString()
                                                 initWithItemIdentifier:idPath.toNSString()
                                                             withUTType: isDir ? UTTypeFolder : UTTypePlainText
                                                             withParent: itemIdentifier
                                                               withSize: isDir ? 0 : size
                                                            withVersion:version.toNSString()
                                                       withCreationDate:creationDate.toNSDate()
                                                   withModificationDate:modificationDate.toNSDate()];
        SharedStateOverview::Instance()->addFileProviderItem(idPath, item);
        if (items != nil)
            [items addObject:item];
    }
    completionHandler();
}

void SharedStateOverview::causeDownload(QString identifier,
                                        NSProgress* progressIndicator,
                                        std::function<void(QString)> completionHandler,
                                        std::function<void(QString)> failureHandler)
{
    qDebug() << "CAUSING DOWNLOAD:" << identifier;

    AccountWorkers* workers = this->findWorkersForIdentifier(identifier);
    
    if (!workers) {
        qWarning() << "Failed to find account workers for" << identifier;
        failureHandler(QString());
        return;
    }
    
    const QString remotePath = findPathForIdentifier(identifier);
    if (remotePath.isEmpty()) {
        qWarning() << "remotePath turned out to be empty:" << identifier;
        failureHandler(QString());
        return;
    }

    // Reuse cached files to not confuse fileproviderd when clearing the cache.
    const QString localPath = FilePathUtil::destination(workers->account()) + remotePath;
    if (QFile::exists(localPath)) {
        completionHandler(localPath);
        return;
    }

    //NSURL* localPathUrl = QUrl::fromLocalFile(localPath).toNSURL();
    //[localPathUrl startAccessingSecurityScopedResource];
    CommandEntity* command = workers->transferCommandQueue()->fileDownloadRequest(remotePath,
                                                                                  "",
                                                                                  false,
                                                                                  QDateTime(),
                                                                                  false);
    
    if (!command) {
        qWarning() << "Received empty download command entity";
        failureHandler(localPath);
        return;
    }
    
    [progressIndicator setTotalUnitCount:100];
    progressIndicator.cancellationHandler = [command](){ command->abort(); };
    
    QObject::connect(command, &CommandEntity::done, this, [=](){
        qDebug() << "Download done" << identifier;
        completionHandler(localPath);
        //[localPathUrl stopAccessingSecurityScopedResource];
        command->deleteLater();
    }, Qt::DirectConnection);

    QObject::connect(command, &CommandEntity::aborted, this, [=](){
        qDebug() << "Download aborted" << identifier;
        failureHandler(localPath);
        //[localPathUrl stopAccessingSecurityScopedResource];
        command->deleteLater();
    }, Qt::DirectConnection);

    QObject::connect(command, &CommandEntity::progressChanged, this, [=](){
        qDebug() << command->progress();
        [progressIndicator setCompletedUnitCount:(command->progress()*100)];
    }, Qt::DirectConnection);
    
    command->run();
}

void SharedStateOverview::causeUpload(FileProviderItem *item,
                                      NSURL* newContents,
                                      NSProgress *progressIndicator,
                                      std::function<void ()> completionHandler,
                                      std::function<void ()> failureHandler,
                                      NSURL* externalCopyUrl,
                                      QString externalFileName)
{
    QString identifier = QString::fromNSString(item.itemIdentifier);
    qDebug() << "CAUSING UPLOAD:" << identifier;
    AccountWorkers* workers = this->findWorkersForIdentifier(identifier);

    if (!workers) {
        qWarning() << "Failed to find account workers for" << identifier;
        failureHandler();
        return;
    }

    // If this is an external copy-to-cloud, then resolve the URL directly, then return.
    if (externalCopyUrl != nil && !externalFileName.isEmpty()) {
        BOOL lockSuccess = [externalCopyUrl startAccessingSecurityScopedResource];
        QString localPath = QUrl::fromNSURL(externalCopyUrl).toLocalFile();
        QString remotePath = findRemoteDirForIdentifier(identifier);

        qDebug() << "CAUSING UPLOAD START:" << remotePath << localPath;

        CommandEntity* command = workers->transferCommandQueue()->fileUploadRequest(localPath,
                                                                                    remotePath + externalFileName,
                                                                                    QFileInfo(localPath).lastModified(),
                                                                                    false);
        
        [progressIndicator setTotalUnitCount:100];
        progressIndicator.cancellationHandler = [command](){ command->abort(); };

        QObject::connect(command, &CommandEntity::done, this, [=](){
            qDebug() << "Upload done" << identifier << localPath << remotePath;
            if (lockSuccess)
                [externalCopyUrl stopAccessingSecurityScopedResource];
            completionHandler();
        }, Qt::DirectConnection);

        QObject::connect(command, &CommandEntity::aborted, this, [=](){
            if (lockSuccess)
                [externalCopyUrl stopAccessingSecurityScopedResource];
            qDebug() << "Upload aborted" << identifier;
            failureHandler();
        }, Qt::DirectConnection);

        QObject::connect(command, &CommandEntity::progressChanged, this, [=](){
            qDebug() << command->progress();
            [progressIndicator setCompletedUnitCount:(command->progress()*100)];
        }, Qt::DirectConnection);

        command->run();
        return;
    }

    NSFileProviderManager* manager = this->providerManager();
    [manager getUserVisibleURLForItemIdentifier:item.itemIdentifier
                              completionHandler:[=](NSURL *userVisibleFile, NSError *error) {
        qDebug() << "userVisibleFile" << userVisibleFile << "Error" << error;

        if (error != nil) {
            qWarning() << "Error:" << error;
            failureHandler();
            return;
        }

        std::function<void()> userVisibleFileReceivedOperation = [=](){
            QString remotePath = findRemoteDirForIdentifier(identifier);
            if (remotePath.isEmpty()) {
                qWarning() << "remotePath turned out to be empty:" << identifier;
                failureHandler();
                return;
            }

            BOOL lockSuccess = [userVisibleFile startAccessingSecurityScopedResource];
            QString localPath = QUrl::fromNSURL(userVisibleFile).toLocalFile();

            qDebug() << "CAUSING UPLOAD START:" << remotePath << localPath;

            CommandEntity* command = workers->transferCommandQueue()->fileUploadRequest(localPath,
                                                                                        remotePath + QFileInfo(localPath).fileName(),
                                                                                        QFileInfo(localPath).lastModified(),
                                                                                        false);

            if (!command) {
                qWarning() << "Received empty upload command entity";
                if (lockSuccess)
                    [userVisibleFile stopAccessingSecurityScopedResource];
                failureHandler();
                return;
            }

            [progressIndicator setTotalUnitCount:100];
            progressIndicator.cancellationHandler = [command](){ command->abort(); };

            QObject::connect(command, &CommandEntity::done, this, [=](){
                qDebug() << "Upload done" << identifier << localPath << remotePath;
                if (lockSuccess)
                    [userVisibleFile stopAccessingSecurityScopedResource];
                completionHandler();
                command->deleteLater();
            }, Qt::DirectConnection);

            QObject::connect(command, &CommandEntity::aborted, this, [=](){
                qDebug() << "Upload aborted" << identifier;
                if (lockSuccess)
                    [userVisibleFile stopAccessingSecurityScopedResource];
                failureHandler();
                command->deleteLater();
            }, Qt::DirectConnection);

            QObject::connect(command, &CommandEntity::progressChanged, this, [=](){
                qDebug() << command->progress();
                [progressIndicator setCompletedUnitCount:(command->progress()*100)];
            }, Qt::DirectConnection);

            qDebug() << "Starting upload...";
            command->run();
            command->waitForFinished();
        };

        runDefaultConnectedOperation(userVisibleFileReceivedOperation);
    }];
}

void SharedStateOverview::causeDirectoryCreation(QString identifier, QString remotePath, std::function<void ()> successHandler, std::function<void ()> failHandler)
{
    AccountWorkers* workers = this->findWorkersForIdentifier(identifier);
    if (!workers) {
        failHandler();
        return;
    }
    CommandEntity* command = workers->transferCommandQueue()->makeDirectoryRequest(remotePath, false);
    if (!command) {
        qWarning() << "Empty dir creation command received";
        failHandler();
        return;
    }

    command->run();
    command->waitForFinished();

    if (command->isFinished()) {
        successHandler();
    } else {
        failHandler();
    }

    command->deleteLater();
}

void SharedStateOverview::causeDelete(QString identifier,
                                      std::function<void()> completionHandler,
                                      std::function<void()> failureHandler)
{
    qDebug() << "CAUSING DELETE:" << identifier;
    AccountWorkers* workers = this->findWorkersForIdentifier(identifier);

    if (!workers) {
        qWarning() << "Failed to find account workers for" << identifier;
        failureHandler();
        return;
    }

    const QString remotePath = findPathForIdentifier(identifier);
    if (remotePath.isEmpty()) {
        qWarning() << "remotePath turned out to be empty:" << identifier;
        failureHandler();
        return;
    }

    CommandEntity* command = workers->transferCommandQueue()->removeRequest(remotePath);
    if (!command) {
        qWarning() << "Received empty download command entity";
        failureHandler();
        return;
    }

    QObject::connect(command, &CommandEntity::done, this, [=](){
        qDebug() << "Removal done" << identifier;
        completionHandler();
        command->deleteLater();
    }, Qt::DirectConnection);

    QObject::connect(command, &CommandEntity::aborted, this, [=](){
        qDebug() << "Removal error" << identifier;
        failureHandler();
        command->deleteLater();
    }, Qt::DirectConnection);

    command->run();
}
