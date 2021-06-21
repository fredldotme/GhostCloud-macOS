//
//  FileProviderHelpers.h
//  FileProvider
//
//  Created by Alfred Neumayer on 20.06.21.
//

#ifndef FileProviderHelpers_h
#define FileProviderHelpers_h

#include <QObject>
#include <QThread>

#include <util/filepathutil.h>

static void runDefaultConnectedOperation(QObject* object, std::function<void()> operation)
{
    if (object && object->thread() != QThread::currentThread()) {
        QMetaObject::invokeMethod(qApp, operation);
    } else {
        operation();
    }
}

static void runDefaultConnectedOperation(std::function<void()> operation)
{
    runDefaultConnectedOperation(qApp, operation);
}

static QString extractNameFromIdentifier(const QString& identifier)
{
#if QT_VERSION < 0x060000
    QStringList crumbs = identifier.split("/", QString::SkipEmptyParts);
#else
    QStringList crumbs = identifier.split("/", Qt::SkipEmptyParts);
#endif
    return crumbs.takeLast();
}

static QString getIdentifierForAccount(AccountBase *account)
{
    if (!account)
        return QString();

    const QString namePattern = QStringLiteral("%1 (%2:%3).dir").arg(account->username(), account->hostname(), QString::number(account->port()));
    return namePattern;
}

static QString getLocalUrlForIdentifier(AccountBase* account, QString identifier)
{
    QString ret = FilePathUtil::destination(account);
    ret += identifier.mid(getIdentifierForAccount(account).length());
    return ret;
}

static QString findPathForIdentifier(QString identifier)
{
#if QT_VERSION < 0x060000
    QStringList pathCrumbs = identifier.split("/", QString::SkipEmptyParts);
#else
    QStringList pathCrumbs = identifier.split("/", Qt::SkipEmptyParts);
#endif
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

static QString findRemoteDirForIdentifier(QString identifier)
{
    QString path = findPathForIdentifier(identifier);

#if QT_VERSION < 0x060000
    QStringList crumbs = path.split("/", QString::SkipEmptyParts);
#else
    QStringList crumbs = path.split("/", Qt::SkipEmptyParts);
#endif

    if (crumbs.length() > 0)
        crumbs.takeLast();
    QString ret = "/" + crumbs.join("/");
    if (!ret.endsWith("/"))
        ret += "/";
    return ret;
}

static NSString* getNewIdentifierForTemplateCreation(NSFileProviderItemIdentifier parent,
                                                     NSString* filename,
                                                     bool isDir)
{
    QString ret = QString::fromNSString(parent);
    if (!ret.endsWith("/"))
        ret += "/";
    ret += QString::fromNSString(filename);
    if (isDir)
        ret += "/";
    return ret.toNSString();
}

#endif /* FileProviderHelpers_h */
