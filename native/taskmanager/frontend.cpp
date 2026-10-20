#include "frontend.h"
#include "collector.h"
#include <QtQuickControls2/QQuickStyle>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QPainter>
#include <QPainterPath>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/signalfd.h>
#include <signal.h>
#ifndef CEDAR_BUILD_ID
#define CEDAR_BUILD_ID "development"
#endif
using namespace CedarTask;
QHash<int,QByteArray> ProcessModel::roleNames()const{return {{Identity,"identity"},{Name,"processName"},{Pid,"pid"},{Cpu,"cpu"},{Rss,"rss"},{Gpu,"gpuMemory"},{State,"processState"},{Owner,"owner"},{Group,"appGroup"},{Protected,"protection"}};}
QVariant ProcessModel::data(const QModelIndex &i,int role)const {
    if(!i.isValid()||i.row()>=rows.size())return {};
    static const QHash<int,QString> keys={{Identity,"identity"},{Name,"name"},{Pid,"pid"},{Cpu,"cpu"},{Rss,"rss"},{Gpu,"gpuMemory"},{State,"state"},{Owner,"user"},{Group,"group"},{Protected,"protected"}};
    return rows[i.row()].value(keys.value(role));
}
void ProcessModel::update(const QJsonArray &values){
    QHash<QString,QVariantMap> incoming;QList<QString> order;
    for(const auto &v:values){auto row=v.toObject().toVariantMap();auto key=row["identity"].toString();if(key.isEmpty()||incoming.contains(key))continue;incoming[key]=row;order.append(key);}
    for(int i=rows.size()-1;i>=0;--i)if(!incoming.contains(rows[i]["identity"].toString())){beginRemoveRows({},i,i);rows.removeAt(i);endRemoveRows();}
    QSet<QString> existing;int first=-1,last=-1;
    for(int i=0;i<rows.size();++i){auto key=rows[i]["identity"].toString();existing.insert(key);if(rows[i]!=incoming[key]){rows[i]=incoming[key];if(first<0)first=i;last=i;}}
    if(first>=0)Q_EMIT dataChanged(index(first),index(last));
    QVector<QVariantMap> added;for(const auto &key:order)if(!existing.contains(key))added.append(incoming[key]);
    if(!added.isEmpty()){auto start=rows.size();beginInsertRows({},start,start+added.size()-1);rows+=added;endInsertRows();}
}
bool ProcessProxy::filterAcceptsRow(int row,const QModelIndex&)const{
    const auto &r=static_cast<ProcessModel*>(sourceModel())->rows[row];
    return (!own||r["uid"].toLongLong()==qint64(getuid()))&&(state.isEmpty()||state==r["state"].toString())&&
        (query.isEmpty()||r["name"].toString().contains(query,Qt::CaseInsensitive)||r["pid"].toString().contains(query)||r["group"].toString().contains(query,Qt::CaseInsensitive));
}
bool ProcessProxy::lessThan(const QModelIndex&a,const QModelIndex&b)const{
    auto *m=static_cast<ProcessModel*>(sourceModel());const auto &l=m->rows[a.row()],&r=m->rows[b.row()];
    if(groups&&l["group"]!=r["group"])return descending?l["group"].toString()>r["group"].toString():l["group"].toString()<r["group"].toString();
    auto x=l.value(sortKey),y=r.value(sortKey);if(x.isNull()!=y.isNull())return descending?x.isNull():!x.isNull();
    if(x==y)return l["identity"].toString()<r["identity"].toString();
    if(sortKey=="name"||sortKey=="state"||sortKey=="user")return QString::localeAwareCompare(x.toString(),y.toString())<0;
    return x.toDouble()<y.toDouble();
}
void HistoryGraph::paint(QPainter *p){
    if(values.size()<2)return;double cap=ceiling;if(cap<=0){cap=1;for(const auto &v:values)if(!v.isNull())cap=std::max(cap,v.toDouble());}
    p->setRenderHint(QPainter::Antialiasing);QPainterPath path;bool started=false;
    for(int i=0;i<values.size();++i){if(values[i].isNull()){started=false;continue;}QPointF point(double(i)/119*width(),height()-std::clamp(values[i].toDouble()/cap,0.0,1.0)*(height()-4)-2);if(!started){path.moveTo(point);started=true;}else path.lineTo(point);}
    p->setPen(QPen(ink,1.6));p->drawPath(path);
}
static QString configPath(){return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)+"/cedar";}
static QVariantMap jsonFile(const QString &p){return QJsonDocument::fromJson(readFile(p)).object().toVariantMap();}
TaskClient::TaskClient(QString source,bool testing,QObject *p):QObject(p),model(this),proxy(this),root(std::move(source)),prefs(configPath()+"/task-manager.ini",QSettings::IniFormat),test(testing){
    proxy.setSourceModel(&model);proxy.sort(0,Qt::DescendingOrder);socketPath=runtimeDirectory()+"/taskd-"+CEDAR_BUILD_ID+".sock";
    reconnect.setSingleShot(true);actionTimer.setSingleShot(true);actionTimer.setInterval(5000);
    connect(&actionTimer,&QTimer::timeout,this,[this]{pending.clear();resultText="Action reply timed out; outcome unknown. Refresh before retrying.";Q_EMIT changed();});
    connect(&reconnect,&QTimer::timeout,this,&TaskClient::connectBackend);
    connect(&socket,&QLocalSocket::connected,this,[this]{if(!sameUserPeer(socket.socketDescriptor())){socket.abort();return;}send({{"type","hello"},{"build",CEDAR_BUILD_ID}});});
    connect(&socket,&QLocalSocket::readyRead,this,&TaskClient::read);
    connect(&socket,&QLocalSocket::disconnected,this,&TaskClient::disconnected);
    connect(&socket,&QLocalSocket::errorOccurred,this,[this](auto){disconnected();});
    backend.setStandardOutputFile(QProcess::nullDevice());backend.setStandardErrorFile(QProcess::nullDevice());
    connect(&backend,&QProcess::errorOccurred,this,[this](auto){stateText="Collector could not start: "+backend.errorString();Q_EMIT changed();});
    watchdog.setInterval(1000);connect(&watchdog,&QTimer::timeout,this,[this]{if(online&&lastSample.isValid()&&lastSample.elapsed()>(visible?5000:15000)){stateText="Collector stopped responding";socket.abort();}});watchdog.start();
    connect(&watcher,&QFileSystemWatcher::fileChanged,this,[this]{loadStyle();});connect(&watcher,&QFileSystemWatcher::directoryChanged,this,[this]{loadStyle();});
    loadStyle();
    if(test && qEnvironmentVariableIsSet("CEDAR_TASK_TEST_LOCAL_COLLECTOR")) {
        auto collector=std::make_shared<Collector>();auto *timer=new QTimer(this);timer->setInterval(1000);
        connect(timer,&QTimer::timeout,this,[this,collector]{auto data=collector->sample();auto rows=data.take("processes").toArray();data["type"]="snapshot";data["sampleIntervalMs"]=1000;receive(data);receive({{"type","processes"},{"rows",rows}});});timer->start();
    } else QTimer::singleShot(0,this,&TaskClient::connectBackend);
}
TaskClient::~TaskClient(){reconnect.stop();socket.abort();if(backend.state()!=QProcess::NotRunning){backend.terminate();if(!backend.waitForFinished(1500)){backend.kill();backend.waitForFinished(1000);}}}
void TaskClient::loadStyle(){
    theme=jsonFile(root+"/themes/palettes/cedar.json").value("colors").toMap();auto overrides=jsonFile(configPath()+"/theme.json").value("colors").toMap();
    for(auto it=overrides.begin();it!=overrides.end();++it)if(QColor::isValidColorName(it.value().toString()))theme[it.key()]=it.value();
    auto settings=jsonFile(configPath()+"/settings.json");theme["font"]=settings.value("interfaceFont","Rajdhani");theme["mono"]=settings.value("dataFont","JetBrainsMono Nerd Font");
    theme["fontScale"]=std::clamp(settings.value("fontScale",1).toDouble(),0.8,1.5);theme["reducedMotion"]=settings.value("reducedMotion",false);theme["radius"]=std::clamp(settings.value("panelRadius",12).toInt(),0,28);
    for(const auto &path:QStringList{configPath(),configPath()+"/settings.json",configPath()+"/theme.json"})if(QFileInfo::exists(path)&&!watcher.files().contains(path)&&!watcher.directories().contains(path))watcher.addPath(path);
    Q_EMIT styleChanged();
}
void TaskClient::send(QJsonObject r){r["protocol"]=Protocol;socket.write(QJsonDocument(r).toJson(QJsonDocument::Compact)+'\n');}
void TaskClient::connectBackend(){
    if(socket.state()==QLocalSocket::ConnectedState||socket.state()==QLocalSocket::ConnectingState)return;
    if(backend.state()==QProcess::NotRunning){auto path=QCoreApplication::applicationDirPath()+"/cedar-taskd";backend.start(path,{});}
    socket.connectToServer(socketPath);
}
void TaskClient::disconnected(){
    online=false;system.clear();model.update({});proxy.invalidate();detail.clear();hist.clear();buffer.clear();
    if(!pending.isEmpty()){pending.clear();actionTimer.stop();resultText="Disconnected before action confirmation; outcome unknown";}
    stateText="Disconnected · reconnecting to the collector";if(!reconnect.isActive()){reconnect.start(retryMs);retryMs=std::min(retryMs*2,5000);}Q_EMIT changed();
}
void TaskClient::read(){
    buffer+=socket.readAll();if(buffer.size()>32*1024*1024){socket.abort();return;}
    while(buffer.contains('\n')){auto n=buffer.indexOf('\n');auto line=buffer.left(n);buffer.remove(0,n+1);QJsonParseError e;auto doc=QJsonDocument::fromJson(line,&e);
        if(e.error!=QJsonParseError::NoError||!doc.isObject()||doc["protocol"].toInt()!=Protocol){socket.abort();return;}receive(doc.object());
    }
}
void TaskClient::receive(QJsonObject r){auto type=r["type"].toString();
        if(type=="hello"){if(r["build"].toString()!=CEDAR_BUILD_ID){socket.abort();return;}retryMs=250;send({{"type","visibility"},{"visible",visible}});}
        else if(type=="snapshot"){
            online=true;stateText="Live · "+QString::number(r["sampleIntervalMs"].toInt()/1000)+" s sampling";lastSample.restart();++sampleCount;system=r.toVariantMap();
            auto append=[&](QString key,QVariant value){auto list=hist.value(key).toList();list.append(value);while(list.size()>120)list.removeFirst();hist[key]=list;};
            append("cpu",r["cpu"].toObject()["percent"].toVariant());append("memory",r["memory"].toObject()["percent"].toVariant());append("swap",r["memory"].toObject()["swapPercent"].toVariant());
            auto gpus=r["gpus"].toArray();for(int i=0;i<gpus.size();++i){auto gpu=gpus[i].toObject();append("gpu"+QString::number(i),gpu["percent"].toVariant());append("vram"+QString::number(i),gpu["used"].toVariant());}
            for(const auto &key:QStringList{"diskRead","diskWrite","download","upload"})append(key,r[key].toVariant());
            auto game=jsonFile((qEnvironmentVariable("XDG_STATE_HOME").isEmpty()?QDir::homePath()+"/.local/state":qEnvironmentVariable("XDG_STATE_HOME"))+"/cedar/gaming.json");gamingText=game.isEmpty()?"Gaming Mode: state unavailable":game.value("active").toBool()?"Gaming Mode active":"Gaming Mode off";
            Q_EMIT changed();
        }else if(type=="processes"){
            model.update(r["rows"].toArray());proxy.invalidate();proxy.sort(0,proxy.descending?Qt::DescendingOrder:Qt::AscendingOrder);updateDetail();Q_EMIT changed();
        }else if(type=="action-result"){
            if(r["id"].toString()==pending){pending.clear();actionTimer.stop();resultText=r["message"].toString();Q_EMIT changed();}
        }else if(type=="error"){stateText=r["message"].toString();Q_EMIT changed();}
}
void TaskClient::visibility(bool value){visible=value;if(socket.state()==QLocalSocket::ConnectedState)send({{"type","visibility"},{"visible",value}});}
void TaskClient::filter(QString query,QString state,bool own,bool groups){proxy.query=query.trimmed();proxy.state=state;proxy.own=own;proxy.groups=groups;proxy.invalidate();proxy.sort(0,proxy.descending?Qt::DescendingOrder:Qt::AscendingOrder);Q_EMIT changed();}
void TaskClient::sort(QString key){if(!QStringList{"name","pid","cpu","rss","gpuMemory","state","user"}.contains(key))return;proxy.descending=proxy.sortKey==key?!proxy.descending:!(key=="name"||key=="state"||key=="user");proxy.sortKey=key;proxy.invalidate();proxy.sort(0,proxy.descending?Qt::DescendingOrder:Qt::AscendingOrder);Q_EMIT changed();}
void TaskClient::select(QString identity){if(selectedId!=identity){hist.remove("processCpu");hist.remove("processMemory");}selectedId=identity;updateDetail();Q_EMIT changed();}
void TaskClient::updateDetail(){
    if(selectedId.isEmpty()){detail.clear();return;}for(const auto &row:model.rows)if(row["identity"].toString()==selectedId){detail=row;for(const auto &pair:QList<QPair<QString,QString>>{{"processCpu","cpu"},{"processMemory","rss"}}){auto list=hist.value(pair.first).toList();list.append(row.value(pair.second));while(list.size()>120)list.removeFirst();hist[pair.first]=list;}return;}
    detail["exited"]=true;detail["cpu"]=QVariant();
}
void TaskClient::action(QString identity,QString operation,int nice,bool confirmed){
    if(!online||!pending.isEmpty())return;const auto parts=identity.split(':');if(parts.size()!=2)return;
    pending=QUuid::createUuid().toString(QUuid::WithoutBraces);resultText="Sending action…";
    send({{"type","action"},{"id",pending},{"pid",parts[0].toLongLong()},{"start",parts[1]},{"action",operation},{"nice",nice},{"confirmed",confirmed}});actionTimer.start();Q_EMIT changed();
}
void TaskClient::refreshServices(){
    if(servicePending)return;
    serviceText="Reading user services…";Q_EMIT servicesChanged();
    auto bus=QDBusConnection::sessionBus();if(!bus.isConnected()){serviceText="User service bus unavailable";units.clear();Q_EMIT servicesChanged();return;}
    auto call=QDBusMessage::createMethodCall("org.freedesktop.systemd1","/org/freedesktop/systemd1","org.freedesktop.systemd1.Manager","ListUnits");
    servicePending=true;auto *pendingCall=new QDBusPendingCallWatcher(bus.asyncCall(call,3000),this);
    connect(pendingCall,&QDBusPendingCallWatcher::finished,this,[this](QDBusPendingCallWatcher *call){servicePending=false;QDBusMessage reply=call->reply();call->deleteLater();units.clear();
        if(reply.type()==QDBusMessage::ErrorMessage||reply.arguments().isEmpty()){serviceText="User services unavailable: "+reply.errorMessage();Q_EMIT servicesChanged();return;}
        const QDBusArgument argument=qvariant_cast<QDBusArgument>(reply.arguments().first());argument.beginArray();while(!argument.atEnd()){
            QString name,description,load,active,sub,following,jobType;QDBusObjectPath path,jobPath;quint32 job;
            argument.beginStructure();argument>>name>>description>>load>>active>>sub>>following>>path>>job>>jobType>>jobPath;argument.endStructure();
            if(name.endsWith(".service"))units.append(QVariantMap{{"name",name},{"description",description},{"state",active+" / "+sub}});
        }argument.endArray();serviceText=QString::number(units.size())+" user services · read-only";Q_EMIT servicesChanged();
    });
}
QVariantMap TaskClient::preferences()const{return {{"width",prefs.value("width",1180)},{"height",prefs.value("height",820)},{"page",prefs.value("page",0)}};}
void TaskClient::savePreferences(int w,int h,int page){if(test)return;prefs.setValue("width",std::clamp(w,520,3840));prefs.setValue("height",std::clamp(h,400,2160));prefs.setValue("page",std::clamp(page,0,3));prefs.sync();}
void TaskClient::finishTest(bool ok,QString reason){qInfo().noquote()<<(ok?"PASS: ":"FAIL: ")+reason;QCoreApplication::exit(ok?0:1);}
bool TaskClient::exerciseModel(){
    QJsonArray rows;for(int i=0;i<6000;++i)rows.append(QJsonObject{{"identity",QString::number(i)+":1"},{"name",QString("fixture %1").arg(i)},{"pid",i},{"uid",qint64(getuid())},{"cpu",i%100},{"rss",i*1000},{"state","S"},{"group","fixture"}});
    QElapsedTimer time;time.start();model.update(rows);filter("fixture 5999","",true,false);bool ok=proxy.rowCount()==1;filter("","",false,true);sort("rss");ok&=proxy.rowCount()==6000;select("5999:1");ok&=detail.value("pid").toInt()==5999;
    rows.removeLast();model.update(rows);updateDetail();ok&=detail.value("exited").toBool();qInfo()<<"6000-row batch/search/sort/selection ms"<<time.elapsed();model.update({});select("");filter("","",false,false);return ok;
}
int main(int argc,char **argv){
    // Block before Qt creates any worker threads; every thread must inherit this
    // mask so SIGTERM reaches signalfd instead of bypassing orderly teardown.
    sigset_t mask;sigemptyset(&mask);sigaddset(&mask,SIGTERM);sigaddset(&mask,SIGINT);sigprocmask(SIG_BLOCK,&mask,nullptr);
    QGuiApplication app(argc,argv);QCoreApplication::setApplicationName("cedar-task-manager");QCoreApplication::setOrganizationName("CEDAR");QGuiApplication::setDesktopFileName("cedar-task-manager");QQuickStyle::setStyle("Basic");umask(0077);
    const auto args=app.arguments();auto at=args.indexOf("--source");QString root=at>=0&&at+1<args.size()?QFileInfo(args[at+1]).canonicalFilePath():QString();
    if(root.isEmpty()||!QFileInfo::exists(root+"/taskmanager/Main.qml")){qCritical()<<"Launch through cedar-task-manager or provide --source <CEDAR release>";return 1;}
    bool test=args.contains("--self-test");bool localTest=test&&qEnvironmentVariableIsSet("CEDAR_TASK_TEST_LOCAL_COLLECTOR");
    try{
        const auto endpoint=runtimeDirectory()+"/task-manager.sock";QLocalSocket previous;previous.connectToServer(endpoint);
        if(previous.waitForConnected(250)&&sameUserPeer(previous.socketDescriptor())){previous.write("focus\n");previous.waitForBytesWritten(500);return 0;}
        QLockFile lock(endpoint+".lock");lock.setStaleLockTime(0);if(!lock.tryLock(1500)){previous.abort();previous.connectToServer(endpoint);if(previous.waitForConnected(1000)&&sameUserPeer(previous.socketDescriptor())){previous.write("focus\n");previous.waitForBytesWritten(500);return 0;}qCritical()<<"Task Manager is already starting or unavailable";return 1;}
        QLocalServer focus;focus.setSocketOptions(QLocalServer::UserAccessOption);struct stat info{};
        if(!lstat(QFile::encodeName(endpoint).constData(),&info)&&(!S_ISSOCK(info.st_mode)||info.st_uid!=getuid()))throw std::runtime_error("Unsafe focus socket");
        QLocalServer::removeServer(endpoint);if(!localTest&&!focus.listen(endpoint))throw std::runtime_error("Cannot create application focus socket");
        TaskClient client(root,test);qmlRegisterType<HistoryGraph>("Cedar.TaskManager",1,0,"HistoryGraph");QQmlApplicationEngine engine;engine.rootContext()->setContextProperty("Task",&client);
        engine.load(QUrl::fromLocalFile(root+"/taskmanager/Main.qml"));if(engine.rootObjects().isEmpty())return 1;auto *window=qobject_cast<QQuickWindow*>(engine.rootObjects()[0]);
        QObject::connect(&focus,&QLocalServer::newConnection,&app,[&]{while(focus.hasPendingConnections()){auto *s=focus.nextPendingConnection();s->setReadBufferSize(64);if(!sameUserPeer(s->socketDescriptor())){s->abort();s->deleteLater();continue;}
            QObject::connect(s,&QLocalSocket::readyRead,&app,[s,window]{if(!s->canReadLine())return;auto line=s->readLine(64);if(line=="focus\n"){window->showNormal();window->raise();window->requestActivate();if(!qEnvironmentVariableIsEmpty("HYPRLAND_INSTANCE_SIGNATURE"))QProcess::startDetached("hyprctl",{"dispatch","focuswindow","class:^(cedar-task-manager)$"});}s->disconnectFromServer();});
            QObject::connect(s,&QLocalSocket::disconnected,s,&QObject::deleteLater);QTimer::singleShot(1000,s,[s]{s->abort();s->deleteLater();});
        }});
        QObject::connect(&app,&QGuiApplication::lastWindowClosed,&app,&QCoreApplication::quit);
        int sigfd=signalfd(-1,&mask,SFD_CLOEXEC|SFD_NONBLOCK);QSocketNotifier termination(sigfd,QSocketNotifier::Read);QObject::connect(&termination,&QSocketNotifier::activated,&app,&QCoreApplication::quit);
        int result=app.exec();if(sigfd>=0)::close(sigfd);focus.close();QLocalServer::removeServer(endpoint);return result;
    }catch(const std::exception &e){qCritical()<<e.what();return 1;}
}
