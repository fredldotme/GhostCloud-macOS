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
    FileProviderItem* getFileProviderItem(const QString& identifier, bool fetchNew = false);
    QVector<AccountBase*> accounts();
    AccountBase* accountForIdentifier(QString identifier);
    QVector<AccountWorkers*> workers();
    AccountWorkerGenerator* generator() override;
    NSFileProviderManager* providerManager();

    AccountWorkers* findWorkersForIdentifier(QString identifier);

    void causeContentListing(QString identifier,
                             NSMutableArray<FileProviderItem*>* items,
                             std::function<void()> completionHandler,
                             std::function<void()> failureHandler);
    void causeDownload(QString identifier,
                       NSProgress* progressIndicator,
                       std::function<void(QString)> completionHandler,
                       std::function<void(QString)> failureHandler);
    void causeUpload(FileProviderItem* item,
                     NSURL* newContents,
                     NSProgress* progressIndicator,
                     std::function<void()> completionHandler,
                     std::function<void()> failureHandler);
    void causeDelete(QString identifier,
                     std::function<void()> completionHandler,
                     std::function<void()> failureHandler);

    void addFileProviderItem(QString identifier, FileProviderItem* item);

private:
    QMap<QString, AccountWorkers*> m_domainWorkers;
    QCoreApplication* m_app = nullptr;
    AccountWorkerGenerator* m_generator = nullptr;
    AccountDb* m_accountDatabase = nullptr;
    QMap<QString, FileProviderItem*> m_fileProviderItemMap;
};

#endif /* SharedStateOverviewController_h */
