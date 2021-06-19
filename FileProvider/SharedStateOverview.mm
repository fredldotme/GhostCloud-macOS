//
//  SharedStateOvrviewController.cpp
//  FileProvider
//
//  Created by Alfred Neumayer on 18.06.21.
//

#include "SharedStateOverview.h"
#include <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <QMutex>
#include <QMutexLocker>

#include <commandqueue.h>
#include <util/filepathutil.h>

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

void SharedStateOverview::initDomain(QString ident)
{
    AccountWorkers* workers = nullptr;
    this->m_domainWorkers.insert(ident, workers);
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

FileProviderItem* SharedStateOverview::getFileProviderItem(const QString& identifier)
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
                                             withSize: 0];
    return item;
}

QString SharedStateOverview::getIdentifierForAccount(AccountBase *account)
{
    if (!account)
        return QString();

    const QString namePattern = QStringLiteral("%1 (%2:%3).dir").arg(account->username(), account->hostname(), QString::number(account->port()));
    return namePattern;
}

AccountWorkers* SharedStateOverview::findWorkersForIdentifier(QString identifier)
{
    AccountWorkers* ret = nullptr;
    QStringList pathCrumbs = identifier.split("/", QString::SkipEmptyParts);
    QString providerIdentifier = "";
    if (pathCrumbs.length() > 0)
        providerIdentifier = pathCrumbs.takeFirst();

    if (providerIdentifier.isEmpty()) {
        qWarning() << "providerIdentifier is empty!" << identifier;
        goto done;
    }

    for (AccountWorkers* potentialWorkers : SharedStateOverview::Instance()->workers()) {
        if (providerIdentifier == SharedStateOverview::Instance()->getIdentifierForAccount(potentialWorkers->account())) {
            ret = potentialWorkers;
            break;
        }
    }

done:
    return ret;
}

QString SharedStateOverview::findPathForIdentifier(QString identifier)
{
    QStringList pathCrumbs = identifier.split("/", QString::SkipEmptyParts);
    QString providerIdentifier = "";
    if (pathCrumbs.length() > 0)
        providerIdentifier = pathCrumbs.takeFirst();

    if (providerIdentifier.isEmpty()) {
        qWarning() << "providerIdentifier turned out to be empty:" << identifier;
        return QString();
    }

    QString path = "/";
    if (pathCrumbs.length() > 0)
        path = "/" + pathCrumbs.join("/");

    return path;
}

bool SharedStateOverview::causeDownload(QString identifier, QString& localPath)
{
    qDebug() << "CAUSING DOWNLOAD:" << identifier;
    AccountWorkers* workers = this->findWorkersForIdentifier(identifier);

    if (!workers) {
        qWarning() << "Failed to find account workers for" << identifier;
        return false;
    }

    const QString remotePath = this->findPathForIdentifier(identifier);
    if (remotePath.isEmpty()) {
        qWarning() << "remotePath turned out to be empty:" << identifier;
        return false;
    }

    CommandEntity* command = workers->transferCommandQueue()->fileDownloadRequest(remotePath,
                                                                                  "",
                                                                                  false,
                                                                                  QDateTime(),
                                                                                  false);
    if (!command) {
        qWarning() << "Received empty download command entity";
        return false;
    }

    QObject::connect(command, &CommandEntity::done, this, [=](){
        qDebug() << "Download done" << identifier;
    });
    QObject::connect(command, &CommandEntity::progressChanged, this, [=](){
        qDebug() << command->progress();
    });
    command->run();
    command->waitForFinished();
    const bool success = command->isFinished();
    localPath = FilePathUtil::destination(workers->account()) + remotePath;
    return success;
}

bool SharedStateOverview::causeDelete(QString identifier)
{
    qDebug() << "CAUSING DELETE:" << identifier;
    AccountWorkers* workers = this->findWorkersForIdentifier(identifier);

    if (!workers) {
        qWarning() << "Failed to find account workers for" << identifier;
        return false;
    }

    const QString remotePath = this->findPathForIdentifier(identifier);
    if (remotePath.isEmpty()) {
        qWarning() << "remotePath turned out to be empty:" << identifier;
        return false;
    }

    CommandEntity* command = workers->transferCommandQueue()->removeRequest(remotePath);
    if (!command) {
        qWarning() << "Received empty download command entity";
        return false;
    }

    QObject::connect(command, &CommandEntity::done, this, [=](){
        qDebug() << "Removal done" << identifier;
    });
    command->run();
    command->waitForFinished();
    const bool success = command->isFinished();
    return success;
}
