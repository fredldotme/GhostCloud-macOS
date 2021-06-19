//
//  SharedStateOverviewController.h
//  FileProvider
//
//  Created by Alfred Neumayer on 18.06.21.
//

#ifndef SharedStateOverviewController_h
#define SharedStateOverviewController_h

#include <QObject>
#include <sharedstatecontroller.h>
#include <accountworkergenerator.h>
#include <settings/db/accountdb.h>
#include <commands/sync/ncdirtreecommandunit.h>

#import "FileProviderItem.h"

class SharedStateOverview : public SharedStateController
{
public:
    static SharedStateOverview* Instance();
    void InitQt();
    SharedStateOverview();

private:
    static SharedStateOverview* s_instance;
    static bool qtInited;

public:
    FileProviderItem* getRootItem();
    FileProviderItem* getFileProviderItem(const QString& identifier);
    QVector<AccountBase*> accounts();
    QVector<AccountWorkers*> workers();
    AccountWorkerGenerator* generator() override;
    void initDomain(QString identifier);
    QString getIdentifierForAccount(AccountBase* account);

    AccountWorkers* findWorkersForIdentifier(QString identifier);
    QString findPathForIdentifier(QString identifier);
    
    bool causeDownload(QString identifier, QString& localPath);
    bool causeDelete(QString identifier);

    void addFileProviderItem(QString identifier, FileProviderItem* item);

private:
    QMap<QString, AccountWorkers*> m_domainWorkers;
    QCoreApplication* m_app = nullptr;
    AccountWorkerGenerator* m_generator = nullptr;
    AccountDb* m_accountDatabase = nullptr;
    QMap<QString, FileProviderItem*> m_fileProviderItemMap;
};

#endif /* SharedStateOverviewController_h */
