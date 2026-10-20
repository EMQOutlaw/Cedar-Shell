#pragma once
#include <QtCore>
#include <QtNetwork>
#include <QtQuick>
#include <QtDBus>
class ProcessModel : public QAbstractListModel {
    Q_OBJECT
public:
    QVector<QVariantMap> rows;
    enum {Identity=Qt::UserRole+1,Name,Pid,Cpu,Rss,Gpu,State,Owner,Group,Protected};
    explicit ProcessModel(QObject *p=nullptr):QAbstractListModel(p){}
    int rowCount(const QModelIndex &p={})const override{return p.isValid()?0:rows.size();}
    QVariant data(const QModelIndex &,int role)const override;
    QHash<int,QByteArray> roleNames()const override;
    void update(const QJsonArray &);
};
class ProcessProxy : public QSortFilterProxyModel {
    Q_OBJECT
public:
    QString query,state,sortKey="cpu";bool own=false,groups=false,descending=true;
    explicit ProcessProxy(QObject *p=nullptr):QSortFilterProxyModel(p){setDynamicSortFilter(false);}
    bool filterAcceptsRow(int,const QModelIndex&)const override;
    bool lessThan(const QModelIndex &,const QModelIndex &)const override;
};
class HistoryGraph : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QVariantList samples READ samples WRITE setSamples NOTIFY samplesChanged)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY samplesChanged)
    Q_PROPERTY(double maximum READ maximum WRITE setMaximum NOTIFY samplesChanged)
    QVariantList values;QColor ink="#3fe0c5";double ceiling=100;
public:
    explicit HistoryGraph(QQuickItem *p=nullptr):QQuickPaintedItem(p){setAntialiasing(true);}
    QVariantList samples()const{return values;}void setSamples(QVariantList v){values=std::move(v);update();Q_EMIT samplesChanged();}
    QColor color()const{return ink;}void setColor(QColor c){ink=c;update();Q_EMIT samplesChanged();}
    double maximum()const{return ceiling;}void setMaximum(double c){ceiling=c;update();Q_EMIT samplesChanged();}
    void paint(QPainter *) override;
Q_SIGNALS:void samplesChanged();
};
class TaskClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap snapshot READ snapshot NOTIFY changed)
    Q_PROPERTY(QVariantMap selected READ selected NOTIFY changed)
    Q_PROPERTY(QVariantMap history READ history NOTIFY changed)
    Q_PROPERTY(QVariantMap style READ style NOTIFY styleChanged)
    Q_PROPERTY(QVariantList services READ services NOTIFY servicesChanged)
    Q_PROPERTY(QString serviceStatus READ serviceStatus NOTIFY servicesChanged)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(bool connected READ connected NOTIFY changed)
    Q_PROPERTY(bool actionPending READ actionPending NOTIFY changed)
    Q_PROPERTY(bool testing READ testing CONSTANT)
    Q_PROPERTY(int samples READ samples NOTIFY changed)
    Q_PROPERTY(QAbstractItemModel* processes READ processes CONSTANT)
    Q_PROPERTY(int processCount READ processCount NOTIFY changed)
    Q_PROPERTY(QString gaming READ gaming NOTIFY changed)
    Q_PROPERTY(QVariantMap preferences READ preferences CONSTANT)
    ProcessModel model;ProcessProxy proxy;
    QLocalSocket socket;QProcess backend;QTimer reconnect,watchdog,actionTimer;QFileSystemWatcher watcher;
    QByteArray buffer;QString root,socketPath,selectedId,stateText="Connecting…",resultText,serviceText="Not checked",gamingText;
    QVariantMap system,detail,hist,theme;QVariantList units;QString pending;QElapsedTimer lastSample;
    QSettings prefs;bool online=false,visible=true,test=false,servicePending=false;int sampleCount=0,retryMs=250;
    void read();void receive(QJsonObject);void send(QJsonObject);void disconnected();void loadStyle();void updateDetail();
public:
    explicit TaskClient(QString source,bool testing,QObject *p=nullptr);
    ~TaskClient() override;
    QVariantMap snapshot()const{return system;}QVariantMap selected()const{return detail;}QVariantMap history()const{return hist;}
    QVariantMap style()const{return theme;}QVariantList services()const{return units;}QString serviceStatus()const{return serviceText;}
    QString status()const{return stateText;}QString message()const{return resultText;}bool connected()const{return online;}bool actionPending()const{return !pending.isEmpty();}
    bool testing()const{return test;}int samples()const{return sampleCount;}QAbstractItemModel *processes(){return &proxy;}int processCount()const{return proxy.rowCount();}
    QString gaming()const{return gamingText;}QVariantMap preferences()const;
    Q_INVOKABLE void connectBackend();
    Q_INVOKABLE void visibility(bool);
    Q_INVOKABLE void filter(QString query,QString state,bool own,bool groups);
    Q_INVOKABLE void sort(QString key);
    Q_INVOKABLE void select(QString identity);
    Q_INVOKABLE void action(QString identity,QString action,int nice=0,bool confirmed=false);
    Q_INVOKABLE void refreshServices();
    Q_INVOKABLE bool restartForTest(){if(!test||qEnvironmentVariableIsSet("CEDAR_TASK_TEST_LOCAL_COLLECTOR"))return false;backend.kill();return true;}
    Q_INVOKABLE void savePreferences(int width,int height,int page);
    Q_INVOKABLE void finishTest(bool ok,QString reason);
    Q_INVOKABLE bool exerciseModel();
    Q_INVOKABLE QString firstIdentity()const{return model.rows.isEmpty()?QString():model.rows.first().value("identity").toString();}
    Q_INVOKABLE bool capture(QQuickWindow *window){return test&&window&&window->grabWindow().save("/tmp/cedar-task-manager.png");}
Q_SIGNALS:
    void changed();void styleChanged();void servicesChanged();
};
