#include "collector.h"
#include <QtNetwork>
#include <sys/stat.h>
#include <unistd.h>
#include <signal.h>
#include <sys/signalfd.h>
#ifndef CEDAR_BUILD_ID
#define CEDAR_BUILD_ID "development"
#endif
using namespace CedarTask;
struct Client {QByteArray buffer;bool ready=false,visible=true; qint64 pid=0;int requests=0;QElapsedTimer rate;QJsonArray previous;};
static void send(QLocalSocket *s,QJsonObject v) {
    v["protocol"]=Protocol;
    if(s->bytesToWrite()>16*1024*1024){s->abort();return;}
    s->write(QJsonDocument(v).toJson(QJsonDocument::Compact)+'\n');
}
int main(int argc,char **argv) {
    QCoreApplication app(argc,argv);umask(0077);
    if(app.arguments().contains("--version")){qInfo().noquote()<<"cedar-taskd protocol"<<Protocol<<CEDAR_BUILD_ID;return 0;}
    if(geteuid()==0){qCritical()<<"Run Task Manager as your desktop user, never root";return 1;}
    try {
        const auto path=runtimeDirectory()+"/taskd-"+CEDAR_BUILD_ID+".sock";
        QLockFile lock(path+".lock");lock.setStaleLockTime(0);if(!lock.tryLock())return 0;
        struct stat st{};if(!lstat(QFile::encodeName(path).constData(),&st)&&(!S_ISSOCK(st.st_mode)||st.st_uid!=getuid()))throw std::runtime_error("Unsafe socket path");
        QLocalServer server;server.setSocketOptions(QLocalServer::UserAccessOption);QLocalServer::removeServer(path);
        if(!server.listen(path))throw std::runtime_error(server.errorString().toStdString());
        auto cleanup=qScopeGuard([&]{server.close();QLocalServer::removeServer(path);});
        sigset_t mask;sigemptyset(&mask);sigaddset(&mask,SIGTERM);sigaddset(&mask,SIGINT);sigprocmask(SIG_BLOCK,&mask,nullptr);
        int sigfd=signalfd(-1,&mask,SFD_CLOEXEC|SFD_NONBLOCK);QSocketNotifier signals(sigfd,QSocketNotifier::Read);QObject::connect(&signals,&QSocketNotifier::activated,&app,&QCoreApplication::quit);
        auto closeSignal=qScopeGuard([&]{if(sigfd>=0)::close(sigfd);});
        Collector collector;QHash<QLocalSocket*,Client> clients;QTimer sample,idle;idle.setSingleShot(true);idle.setInterval(5000);QObject::connect(&idle,&QTimer::timeout,&app,&QCoreApplication::quit);idle.start();
        auto demand=[&]{bool visible=false,any=false;for(const auto &c:clients){any|=c.ready;visible|=c.ready&&c.visible;}if(any){idle.stop();sample.setInterval(visible?1000:5000);if(!sample.isActive())sample.start();}else{sample.stop();if(!idle.isActive())idle.start();}};
        auto error=[&](QLocalSocket *s,QString text){send(s,{{"type","error"},{"message",text}});s->disconnectFromServer();};
        QObject::connect(&server,&QLocalServer::newConnection,&app,[&]{while(server.hasPendingConnections()){
            auto *s=server.nextPendingConnection();qint64 peer=0;
            if(clients.size()>=8||!sameUserPeer(s->socketDescriptor(),&peer)){s->abort();s->deleteLater();continue;}
            Client c;c.pid=peer;c.rate.start();clients.insert(s,c);s->setReadBufferSize(16384);
            QTimer::singleShot(3000,s,[&,s]{if(clients.contains(s)&&!clients[s].ready)error(s,"Handshake timed out");});
            QObject::connect(s,&QLocalSocket::disconnected,&app,[&,s]{clients.remove(s);s->deleteLater();demand();},Qt::QueuedConnection);
            QObject::connect(s,&QLocalSocket::readyRead,&app,[&,s]{if(!clients.contains(s))return;auto &c=clients[s];c.buffer+=s->readAll();
                if(c.buffer.size()>8192){error(s,"Request exceeds 8192 bytes");return;}
                while(c.buffer.contains('\n')){auto i=c.buffer.indexOf('\n');auto line=c.buffer.left(i);c.buffer.remove(0,i+1);
                    if(c.rate.elapsed()>=1000){c.requests=0;c.rate.restart();}if(++c.requests>20){error(s,"Request rate exceeded");return;}
                    QJsonParseError e{};auto doc=QJsonDocument::fromJson(line,&e);if(e.error!=QJsonParseError::NoError||!doc.isObject()){error(s,"Invalid JSON object");return;}
                    auto r=doc.object();if(r["protocol"].toInt(-1)!=Protocol){error(s,"Incompatible protocol");return;}
                    const auto type=r["type"].toString();QSet<QString> allowed={"type","protocol"};
                    if(type=="hello")allowed.unite({"build"});else if(type=="visibility")allowed.insert("visible");else if(type=="action")allowed.unite({"id","action","pid","start","nice","confirmed"});
                    for(auto it=r.begin();it!=r.end();++it)if(!allowed.contains(it.key())){error(s,"Unknown request field");return;}
                    if(type=="hello"&&!c.ready){if(r["build"].toString()!=CEDAR_BUILD_ID){error(s,"Backend and frontend builds differ; reopen Task Manager");return;}
                        c.ready=true;send(s,{{"type","hello"},{"build",CEDAR_BUILD_ID},{"uid",qint64(getuid())},{"capabilities",QJsonArray{"cpu","memory","processes","disks","network","optional-nvml","pidfd-signals","nice"}}});demand();
                    }else if(!c.ready){error(s,"Handshake required");return;
                    }else if(type=="visibility"&&r["visible"].isBool()){c.visible=r["visible"].toBool();demand();
                    }else if(type=="action"){
                        if(!r["id"].isString()||r["id"].toString().size()>80||!r["pid"].isDouble()||r["pid"].toDouble()!=double(r["pid"].toInteger())){error(s,"Invalid action fields");return;}
                        QSet<qint64> protectedPids={qint64(getpid()),c.pid};
                        for(qint64 pid:c.pid?QList<qint64>{c.pid,qint64(getpid())}:QList<qint64>{qint64(getpid())})for(int depth=0;pid>1&&depth<128;++depth){protectedPids.insert(pid);auto p=inspectProcess(pid);auto next=p["ppid"].toInteger();if(next==pid)break;pid=next;}
                        auto result=processAction(r,protectedPids);result["type"]="action-result";result["id"]=r["id"];result["pid"]=r["pid"];result["start"]=r["start"];send(s,result);
                    }else{error(s,"Unsupported request");return;}
                }
            });
        }});
        quint64 sequence=0;
        QObject::connect(&sample,&QTimer::timeout,&app,[&]{auto snapshot=collector.sample();auto processes=snapshot.take("processes").toArray();snapshot["type"]="snapshot";snapshot["sequence"]=double(++sequence);snapshot["sampleIntervalMs"]=sample.interval();
            for(auto it=clients.begin();it!=clients.end();++it){if(!it->ready)continue;send(it.key(),snapshot);if(processes!=it->previous){send(it.key(),{{"type","processes"},{"sequence",double(sequence)},{"rows",processes}});it->previous=processes;}}
        });
        return app.exec();
    }catch(const std::exception &e){qCritical().noquote()<<e.what();return 1;}
}
