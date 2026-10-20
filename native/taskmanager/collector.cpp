// Linux sampling techniques reviewed against btop 4792b070 (Apache-2.0).
// Independently implemented; provenance and accounting decisions: docs/TASK-MANAGER.md.
#include "collector.h"
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/syscall.h>
#include <sys/resource.h>
#include <sys/ptrace.h>
#include <sys/wait.h>
#include <unistd.h>
#include <pwd.h>
#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <cerrno>
#include <cmath>
#include <limits>

namespace CedarTask {
QByteArray readFile(const QString &path, qint64 limit) {
    QFile f(path); if (!f.open(QIODevice::ReadOnly)) return {};
    return f.read(limit);
}
static QList<QByteArray> words(QByteArray line) { return line.simplified().split(' '); }
std::optional<CpuTimes> parseCpu(const QByteArray &line) {
    const auto w=words(line); if(w.size()<5 || !w[0].startsWith("cpu")) return {};
    CpuTimes t;
    for(int i=1;i<std::min(qsizetype(9),w.size());++i) {
        bool ok=false; auto v=w[i].toULongLong(&ok); if(!ok) return {};
        t.total+=v; if(i==4 || i==5) t.idle+=v;
    } // guest and guest_nice are already included in user/nice, never add twice.
    return t;
}
QJsonValue cpuUsage(CpuTimes now,std::optional<CpuTimes> before) {
    if(!before || now.total<=before->total || now.idle<before->idle) return QJsonValue();
    auto dt=now.total-before->total, idle=now.idle-before->idle;
    if(idle>dt) return QJsonValue();
    return 100.0*double(dt-idle)/double(dt);
}
QJsonObject parseMemory(const QByteArray &text) {
    QHash<QByteArray,quint64> v;
    for(const auto &line:text.split('\n')) { auto w=words(line); if(w.size()>=2) v[w[0]]=w[1].toULongLong()*1024; }
    if(!v.contains("MemTotal:") || !v["MemTotal:"]) return {{"error","Memory readings unavailable"}};
    const auto total=v["MemTotal:"], cache=v["Cached:"]+v["SReclaimable:"];
    const auto available=std::min(total,v.contains("MemAvailable:")?v["MemAvailable:"]:v["MemFree:"]+v["Buffers:"]+cache);
    const auto swap=v["SwapTotal:"], freeSwap=std::min(swap,v["SwapFree:"]);
    return {{"total",double(total)},{"available",double(available)},{"used",double(total-available)},
        {"cache",double(cache)},{"buffers",double(v["Buffers:"])},{"percent",100.0*double(total-available)/double(total)},
        {"swapTotal",double(swap)},{"swapUsed",double(swap-freeSwap)},
        {"swapPercent",swap?QJsonValue(100.0*double(swap-freeSwap)/double(swap)):QJsonValue()}};
}
QJsonObject parseProcess(const QByteArray &stat,qint64 pageSize) {
    const auto open=stat.indexOf('('), close=stat.lastIndexOf(')');
    if(open<1 || close<=open) return {};
    bool ok=false; const auto pid=stat.left(open).trimmed().toLongLong(&ok); if(!ok || pid<=0) return {};
    auto f=words(stat.mid(close+1)); if(f.size()<22 || f[0].size()!=1) return {};
    auto number=[&](int i){bool valid=false; auto n=f[i].toLongLong(&valid);ok=ok&&valid;return n;};
    auto parent=number(1),session=number(3),ticks=number(11)+number(12),nice=number(16),threads=number(17),start=number(19),rss=number(21);
    if(!ok || start<0 || ticks<0 || rss<0 || threads<0) return {};
    return {{"pid",pid},{"ppid",parent},{"session",session},{"name",QString::fromUtf8(stat.mid(open+1,close-open-1))},
        {"state",QString::fromLatin1(f[0])},{"ticks",QString::number(ticks)},{"start",QString::number(start)},
        {"identity",QString::number(pid)+":"+QString::number(start)},{"rss",double(rss)*double(pageSize)},
        {"nice",nice},{"threads",threads}};
}
QJsonObject inspectProcess(qint64 pid,const QString &root) {
    const QString base=root+"/"+QString::number(pid);
    auto result=parseProcess(readFile(base+"/stat",8192),sysconf(_SC_PAGESIZE)); if(result.isEmpty())return {};
    const auto status=readFile(base+"/status",65536);
    bool found=false, same=true; qint64 uid=-1;
    for(const auto &line:status.split('\n')) if(line.startsWith("Uid:")) {
        auto w=words(line); if(w.size()!=5)break;
        found=true;uid=w[1].toLongLong();for(int i=1;i<5;++i)same=same&&(w[i].toLongLong()==qint64(getuid()));break;
    }
    result["uid"]=uid;result["sameUser"]=found&&same;
    result["exe"]=QFileInfo(base+"/exe").symLinkTarget();
    auto command=readFile(base+"/cmdline",16384);command.replace('\0',' ');
    result["command"]=QString::fromUtf8(command).trimmed();
    result["cgroup"]=QString::fromUtf8(readFile(base+"/cgroup",16384)).trimmed();
    const auto executable=QFileInfo(result["exe"].toString()).fileName();
    result["group"]=executable.isEmpty()?result["name"]:QJsonValue(executable);
    if(executable=="cedar-task-manager"||executable=="cedar-taskd")result["group"]="CEDAR";
    if(executable.startsWith("python")||executable=="qs"||executable=="quickshell"){
        for(const auto &argument:readFile(base+"/cmdline",16384).split('\0')){
            QFileInfo file(QString::fromUtf8(argument));if(!file.isAbsolute()||!file.exists())continue;
            QDir parent=file.dir();if(parent.dirName()=="scripts")parent.cdUp();
            if(QFileInfo::exists(parent.filePath("data/branding.json"))&&QFileInfo::exists(parent.filePath("shell.qml")))result["group"]="CEDAR";
        }
    }
    // Recheck after ancillary reads, which may race an exit or PID reuse.
    if(parseProcess(readFile(base+"/stat",8192),sysconf(_SC_PAGESIZE))["start"]!=result["start"])return {};
    return result;
}
QString runtimeDirectory() {
    const QString base=qEnvironmentVariable("XDG_RUNTIME_DIR"); struct stat s{};
    if(base.isEmpty() || !QDir::isAbsolutePath(base) || lstat(QFile::encodeName(base).constData(),&s) || !S_ISDIR(s.st_mode) || s.st_uid!=getuid() || (s.st_mode&0077))
        throw std::runtime_error("XDG_RUNTIME_DIR must be a private user-owned directory");
    const auto dir=base+"/cedar";
    if(mkdir(QFile::encodeName(dir).constData(),0700)&&errno!=EEXIST)throw std::runtime_error("Cannot create CEDAR runtime directory");
    if(lstat(QFile::encodeName(dir).constData(),&s)||!S_ISDIR(s.st_mode)||s.st_uid!=getuid()||(s.st_mode&0077))throw std::runtime_error("Unsafe CEDAR runtime directory");
    return dir;
}
bool sameUserPeer(qintptr fd,qint64 *pid) {
    ucred c{};socklen_t n=sizeof(c);if(getsockopt(int(fd),SOL_SOCKET,SO_PEERCRED,&c,&n)||c.uid!=getuid()||c.pid<=0)return false;
    if(pid)*pid=c.pid;return true;
}
QString protectedReason(const QJsonObject &p,const QSet<qint64> &protectedPids) {
    auto pid=p["pid"].toInteger();if(pid<=1 || protectedPids.contains(pid))return "Task Manager or its session ancestor is protected";
    if(!p["sameUser"].toBool())return "Only processes wholly owned by your user can be managed";
    if(p["exe"].toString().isEmpty())return "Executable identity is inaccessible";
    if(pid==p["session"].toInteger())return "Session leader is protected";
    const auto cg=p["cgroup"].toString();
    if(cg.contains("/init.scope")||(cg.contains("/session.slice/")&&cg.trimmed().endsWith(".service")))return "Session infrastructure is protected";
    const auto exe=QFileInfo(p["exe"].toString()).fileName().toLower();
    static const QSet<QString> critical={"hyprland","sway","niri","kwin_wayland","gnome-shell","systemd","dbus-daemon","dbus-broker","pipewire","wireplumber","qs","quickshell","cedar-taskd","cedar-task-manager"};
    if(critical.contains(exe))return "Desktop/session component is protected";
    if(p["group"].toString()=="CEDAR")return "CEDAR service is protected";
    return {};
}
static QJsonObject failure(const QString &code,const QString &message) {return {{"ok",false},{"code",code},{"message",message}};}
// A short-lived tracer holds the numeric PID until scheduling has completed.
// Never fall back to an unguarded setpriority. Yama/LSM restrictions are honored.
static int guardedPriority(qint64 pid,const QString &start,int value,int pidfd) {
    int channel[2];if(pipe2(channel,O_CLOEXEC))return errno;
    auto child=fork();
    if(child<0){int error=errno;close(channel[0]);close(channel[1]);return error;}
    if(child==0){
        close(channel[0]);int result=0;
        auto finish=[&](int error){::write(channel[1],&error,sizeof(error));_exit(0);};
        if(ptrace(PTRACE_SEIZE,pid,nullptr,nullptr)<0)finish(errno);
        // Exiting this helper always detaches; EXITKILL is deliberately absent.
        pollfd live{pidfd,POLLIN,0};
        if(poll(&live,1,0)!=0||inspectProcess(pid)["start"].toString()!=start)finish(ESRCH);
        if(ptrace(PTRACE_INTERRUPT,pid,nullptr,nullptr)<0)finish(errno);
        int status=0;bool stopped=false;
        for(int i=0;i<200;++i){auto waited=waitpid(pid,&status,WNOHANG|__WALL);
            if(waited==pid){stopped=WIFSTOPPED(status);break;}
            if(waited<0)break;usleep(1000);
        }
        if(!stopped)finish(EBUSY);
        if(poll(&live,1,0)!=0||inspectProcess(pid)["start"].toString()!=start)finish(ESRCH);
        // Traced stopped tasks cannot be reaped/reused before this tracer releases them.
        if(setpriority(PRIO_PROCESS,id_t(pid),value)<0)result=errno;
        int signal=(unsigned(status)>>16)==PTRACE_EVENT_STOP?0:WSTOPSIG(status);
        if(ptrace(PTRACE_DETACH,pid,nullptr,reinterpret_cast<void*>(qintptr(signal)))<0&&!result)result=errno;
        finish(result);
    }
    close(channel[1]);int result=EIO;pollfd reply{channel[0],POLLIN,0};
    if(poll(&reply,1,1000)>0&&::read(channel[0],&result,sizeof(result))==sizeof(result)){}
    else {kill(child,SIGKILL);result=ETIMEDOUT;}
    close(channel[0]);while(waitpid(child,nullptr,0)<0&&errno==EINTR){}return result;
}
QJsonObject processAction(const QJsonObject &r,const QSet<qint64> &protectedPids) {
    const qint64 pid=r["pid"].toInteger(-1);const auto start=r["start"].toString(),action=r["action"].toString();
    if(pid<2||pid>INT_MAX||start.isEmpty()||!QRegularExpression("^[0-9]{1,20}$").match(start).hasMatch())return failure("invalid","Invalid process identity");
    const QHash<QString,int> signals={{"term",SIGTERM},{"kill",SIGKILL},{"stop",SIGSTOP},{"continue",SIGCONT}};
    if(!signals.contains(action)&&action!="nice")return failure("unsupported","Unsupported process action");
    if(action=="kill"&&!r["confirmed"].toBool())return failure("confirmation","Force Stop requires explicit confirmation");
    int fd=int(syscall(SYS_pidfd_open,int(pid),0));
    if(fd<0)return failure(errno==ESRCH?"exited":"unsupported",errno==ESRCH?"Process already exited":"Cannot obtain a safe process handle: "+QString::fromLocal8Bit(strerror(errno)));
    auto closeFd=qScopeGuard([&]{::close(fd);});
    auto p=inspectProcess(pid);if(p.isEmpty())return failure("exited","Process already exited or is inaccessible");
    if(p["start"].toString()!=start)return failure("identity","Process exited; PID now belongs to another process");
    auto reason=protectedReason(p,protectedPids);if(!reason.isEmpty())return failure("protected",reason);
    pollfd live{fd,POLLIN,0};if(poll(&live,1,0)>0)return failure("exited","Process already exited");
    int status;
    if(action=="nice") {
        if(!r["nice"].isDouble()||r["nice"].toDouble()!=r["nice"].toInt()||r["nice"].toInt() < -20||r["nice"].toInt()>19)return failure("invalid","Nice value must be an integer between -20 and 19");
        if(p["state"].toString()=="T"||p["state"].toString()=="t")return failure("unsupported","Resume the process before changing priority");
        int error=guardedPriority(pid,start,r["nice"].toInt(),fd);
        if(error)return failure(error==ESRCH?"exited":error==EPERM||error==EACCES?"denied":"unsupported",
            "Safe priority change refused: "+QString::fromLocal8Bit(strerror(error))+". The kernel must permit temporary process tracing.");
        status=0;
    } else status=int(syscall(SYS_pidfd_send_signal,fd,signals[action],nullptr,0));
    if(status<0)return failure(errno==ESRCH?"exited":errno==EPERM||errno==EACCES?"denied":"failed",QString::fromLocal8Bit(strerror(errno)));
    if(action=="nice"&&(poll(&live,1,0)>0||inspectProcess(pid)["start"].toString()!=start))return failure("exited","Process exited during priority change; result unavailable");
    return {{"ok",true},{"code","accepted"},{"message",action=="nice"?"Priority updated":action=="continue"?"Resume signal delivered":action=="stop"?"Suspend signal delivered":action=="kill"?"Force Stop signal delivered":"End Process signal delivered; waiting for exit"}};
}
// NVML ABI subset. No CUDA SDK or NVIDIA library is required at build time.
using Device=void*; struct Util {unsigned gpu,memory;};struct Memory {unsigned long long total,free,used;};
struct GpuProcess {unsigned pid;unsigned long long used;unsigned instance,computeInstance;};
GpuCollector::GpuCollector(QString libraryName):library(std::move(libraryName)) {
    if(library.load()) {auto init=reinterpret_cast<int(*)()>(library.resolve("nvmlInit_v2"));initialized=init&&init()==0;}
}
GpuCollector::~GpuCollector(){if(initialized){auto stop=reinterpret_cast<int(*)()>(library.resolve("nvmlShutdown"));if(stop)stop();}}
QJsonArray GpuCollector::sample(QHash<qint64,quint64> &processMemory,QString &status) {
    QJsonArray rows;if(!initialized){status="NVML unavailable; GPU metrics unsupported on this device";return rows;}
    auto countFn=reinterpret_cast<int(*)(unsigned*)>(library.resolve("nvmlDeviceGetCount_v2"));
    auto handleFn=reinterpret_cast<int(*)(unsigned,Device*)>(library.resolve("nvmlDeviceGetHandleByIndex_v2"));unsigned count=0;
    if(!countFn||!handleFn||countFn(&count)){status="NVIDIA devices inaccessible";return rows;}
    for(unsigned i=0;i<std::min(count,64u);++i){Device dev{};if(handleFn(i,&dev))continue;
        QJsonObject row{{"id",int(i)},{"name","NVIDIA GPU"},{"percent",QJsonValue()},{"used",QJsonValue()},{"total",QJsonValue()},{"temperature",QJsonValue()},{"power",QJsonValue()},{"clock",QJsonValue()}};
        auto name=reinterpret_cast<int(*)(Device,char*,unsigned)>(library.resolve("nvmlDeviceGetName"));char label[256]{};if(name&&!name(dev,label,sizeof(label)))row["name"]=QString::fromUtf8(label);
        auto util=reinterpret_cast<int(*)(Device,Util*)>(library.resolve("nvmlDeviceGetUtilizationRates"));Util u{};if(util&&!util(dev,&u))row["percent"]=int(u.gpu);
        auto memory=reinterpret_cast<int(*)(Device,Memory*)>(library.resolve("nvmlDeviceGetMemoryInfo"));Memory m{};if(memory&&!memory(dev,&m)){row["used"]=double(m.used);row["total"]=double(m.total);}
        auto temp=reinterpret_cast<int(*)(Device,unsigned,unsigned*)>(library.resolve("nvmlDeviceGetTemperature"));unsigned v=0;if(temp&&!temp(dev,0,&v))row["temperature"]=int(v);
        auto power=reinterpret_cast<int(*)(Device,unsigned*)>(library.resolve("nvmlDeviceGetPowerUsage"));if(power&&!power(dev,&v))row["power"]=double(v)/1000;
        auto clock=reinterpret_cast<int(*)(Device,unsigned,unsigned*)>(library.resolve("nvmlDeviceGetClockInfo"));if(clock&&!clock(dev,0,&v))row["clock"]=int(v);
        QHash<qint64,quint64> perDevice;
        for(const auto symbol:{"nvmlDeviceGetComputeRunningProcesses_v2","nvmlDeviceGetGraphicsRunningProcesses_v2"}){
            auto fn=reinterpret_cast<int(*)(Device,unsigned*,GpuProcess*)>(library.resolve(symbol));if(!fn)continue;
            unsigned n=0;int code=fn(dev,&n,nullptr);if(code!=7&&code!=0)continue;if(n>16384)continue;
            QVector<GpuProcess> processes(n+32);n=unsigned(processes.size());if(fn(dev,&n,processes.data()))continue;
            for(unsigned j=0;j<std::min(n,unsigned(processes.size()));++j){auto p=processes[int(j)];if(p.used!=ULLONG_MAX)perDevice[p.pid]=std::max(perDevice.value(p.pid),quint64(p.used));}
        }
        for(auto it=perDevice.begin();it!=perDevice.end();++it)processMemory[it.key()]+=it.value();
        rows.append(row);
    }
    status=rows.isEmpty()?"No accessible NVIDIA GPUs":"NVML; unsupported individual metrics remain unavailable";return rows;
}
Collector::Collector(QString procRoot,QString sysRoot):proc(std::move(procRoot)),sys(std::move(sysRoot)) {
    elapsed.start();
    for(const auto &line:readFile(proc+"/cpuinfo").split('\n'))if(line.startsWith("model name")){cpuModel=QString::fromUtf8(line.mid(line.indexOf(':')+1)).trimmed();break;}
    QDirIterator it(sys+"/class/hwmon",QDir::Dirs|QDir::NoDotAndDotDot);
    while(it.hasNext()){auto dir=it.next();auto name=readFile(dir+"/name").trimmed();if(name!="coretemp"&&name!="k10temp"&&name!="zenpower"&&name!="cpu_thermal")continue;
        for(const auto &f:QDir(dir).entryList({"temp*_input"},QDir::Files))temperaturePaths.append(dir+"/"+f);
    }
}
QJsonObject Collector::sample() {
    QElapsedTimer cost;cost.start();const auto now=elapsed.nsecsElapsed();double seconds=previousNs?double(now-previousNs)/1e9:0;previousNs=now;
    QJsonArray errors,cores;QJsonValue totalCpu;QHash<QString,CpuTimes> nextCpu;
    for(const auto &line:readFile(proc+"/stat").split('\n')){if(!line.startsWith("cpu"))continue;auto t=parseCpu(line);if(!t)continue;auto name=QString::fromLatin1(words(line)[0]);
        auto value=cpuUsage(*t,cpuBefore.contains(name)?std::optional<CpuTimes>(cpuBefore[name]):std::nullopt);nextCpu[name]=*t;
        if(name=="cpu")totalCpu=value;else cores.append(QJsonObject{{"name",name},{"percent",value}});
    }
    if(nextCpu.isEmpty())errors.append("CPU counters unavailable");cpuBefore=nextCpu;
    QJsonValue temperature;double hottest=-273;for(const auto &p:temperaturePaths){bool ok=false;double t=readFile(p,64).trimmed().toDouble(&ok)/1000;if(ok&&t>-20&&t<150)hottest=std::max(hottest,t);}if(hottest>-273)temperature=hottest;
    QJsonValue mhz;bool frequencyOk=false;auto khz=readFile(sys+"/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq",64).trimmed().toDouble(&frequencyOk);if(frequencyOk)mhz=khz/1000;
    auto loadWords=words(readFile(proc+"/loadavg",256));QJsonArray load;for(int i=0;i<3&&i<loadWords.size();++i){bool ok=false;auto n=loadWords[i].toDouble(&ok);load.append(ok?QJsonValue(n):QJsonValue());}
    auto memory=parseMemory(readFile(proc+"/meminfo",65536));if(memory.contains("error"))errors.append(memory["error"]);
    QHash<qint64,quint64> gpuMemory;QString gpuStatus;auto gpus=gpu.sample(gpuMemory,gpuStatus);
    auto uptimeWords=words(readFile(proc+"/uptime",256));double uptime=uptimeWords.value(0).toDouble();
    QJsonArray processes;QHash<QString,quint64> nextTicks;int skipped=0,omitted=0;qsizetype processBytes=0;
    const auto entries=QDir(proc).entryList(QDir::Dirs|QDir::NoDotAndDotDot,QDir::Name);
    for(const auto &name:entries){bool ok=false;qint64 pid=name.toLongLong(&ok);if(!ok||pid<=0)continue;
        auto p=inspectProcess(pid,proc);if(p.isEmpty()){++skipped;continue;}
        auto key=p["identity"].toString();quint64 ticks=p["ticks"].toString().toULongLong();
        p["cpu"]=seconds>0&&ticksBefore.contains(key)&&ticks>=ticksBefore[key]?QJsonValue(100.0*double(ticks-ticksBefore[key])/double(sysconf(_SC_CLK_TCK))/seconds):QJsonValue();nextTicks[key]=ticks;
        auto uid=uint(p["uid"].toInteger());if(!owners.contains(uid)){auto *u=getpwuid(uid);owners[uid]=u?QString::fromLocal8Bit(u->pw_name):QString::number(uid);}p["user"]=owners[uid];
        p["runtime"]=std::max(0.0,uptime-p["start"].toString().toDouble()/double(sysconf(_SC_CLK_TCK)));
        p["gpuMemory"]=gpuMemory.contains(pid)?QJsonValue(double(gpuMemory[pid])):QJsonValue();
        p["protected"]=protectedReason(p,{qint64(getpid())});
        const auto bytes=QJsonDocument(p).toJson(QJsonDocument::Compact).size();
        if(processes.size()>=20000||processBytes+bytes>24*1024*1024){++omitted;continue;}
        processBytes+=bytes+1;processes.append(p);
    }
    ticksBefore=nextTicks;
    if(omitted)errors.append(QString("Process table limit reached; %1 records omitted").arg(omitted));
    QJsonArray networks,disks,mounts;QHash<QString,QPair<quint64,quint64>> nextNet,nextIo;
    auto rate=[&](quint64 current,quint64 old,bool valid)->QJsonValue{return valid&&seconds>0&&current>=old?QJsonValue(double(current-old)/seconds):QJsonValue();};
    double rxTotal=0,txTotal=0,readTotal=0,writeTotal=0;
    auto netText=readFile(proc+"/net/dev");if(netText.isEmpty())errors.append("Network counters unavailable");
    for(const auto &line:netText.split('\n')){auto colon=line.indexOf(':');if(colon<0)continue;auto name=QString::fromUtf8(line.left(colon)).trimmed();auto w=words(line.mid(colon+1));if(w.size()<16)continue;
        auto rx=w[0].toULongLong(),tx=w[8].toULongLong();auto before=netBefore.value(name);bool valid=netBefore.contains(name);auto down=rate(rx,before.first,valid),up=rate(tx,before.second,valid);nextNet[name]={rx,tx};
        networks.append(QJsonObject{{"name",name},{"received",double(rx)},{"sent",double(tx)},{"download",down},{"upload",up},{"state",QString::fromUtf8(readFile(sys+"/class/net/"+name+"/operstate",64)).trimmed()}});
        if(name!="lo"){rxTotal+=down.toDouble();txTotal+=up.toDouble();}
    }netBefore=nextNet;
    auto diskText=readFile(proc+"/diskstats");if(diskText.isEmpty())errors.append("Disk counters unavailable");
    for(const auto &line:diskText.split('\n')){auto w=words(line);if(w.size()<14)continue;QString name=QString::fromLatin1(w[2]);
        if(name.startsWith("loop")||name.startsWith("ram")||QFileInfo::exists(sys+"/class/block/"+name+"/partition"))continue;
        // Leaf block devices only: do not sum a device-mapper layer and its slaves.
        if(!QDir(sys+"/class/block/"+name+"/slaves").entryList(QDir::Dirs|QDir::NoDotAndDotDot).isEmpty())continue;
        auto rd=w[5].toULongLong()*512,wr=w[9].toULongLong()*512;auto before=ioBefore.value(name);bool valid=ioBefore.contains(name);auto read=rate(rd,before.first,valid),write=rate(wr,before.second,valid);nextIo[name]={rd,wr};
        disks.append(QJsonObject{{"name",name},{"read",read},{"write",write},{"inFlight",w[11].toInt()}});readTotal+=read.toDouble();writeTotal+=write.toDouble();
    }ioBefore=nextIo;
    // mountinfo provides device identity; duplicate bind mounts count once.
    QSet<QString> devices;
    for(const auto &line:readFile(proc+"/self/mountinfo").split('\n')){auto w=line.split(' ');auto sep=w.indexOf("-");if(sep<6||w.size()<sep+3)continue;
        auto dev=QString::fromLatin1(w[2]);const auto fs=QString::fromLatin1(w[sep+1]);
        const auto identity=fs=="btrfs"?QString::fromUtf8(w[sep+2]):dev;
        if(devices.contains(identity)||(dev.startsWith("0:")&&fs!="btrfs"))continue;
        QByteArray mount=w[4];mount.replace("\\040"," ");mount.replace("\\011","\t");mount.replace("\\134","\\");struct statvfs v{};
        // Only block-device filesystems. Avoid remote mounts that can block statvfs.
        if((!QFileInfo::exists(sys+"/dev/block/"+dev)&&fs!="btrfs")||statvfs(mount.constData(),&v))continue;devices.insert(identity);
        mounts.append(QJsonObject{{"device",dev},{"path",QString::fromUtf8(mount)},{"filesystem",QString::fromLatin1(w[sep+1])},
            {"total",double(v.f_blocks)*v.f_frsize},{"used",double(v.f_blocks-v.f_bfree)*v.f_frsize},{"available",double(v.f_bavail)*v.f_frsize}});
    }
    return {{"cpu",QJsonObject{{"percent",totalCpu},{"cores",cores},{"model",cpuModel},{"logical",cores.size()},{"mhz",mhz},{"temperature",temperature},{"load",load}}},
        {"memory",memory},{"gpus",gpus},{"gpuStatus",gpuStatus},{"disks",disks},{"mounts",mounts},{"networks",networks},
        {"diskRead",seconds>0?QJsonValue(readTotal):QJsonValue()},{"diskWrite",seconds>0?QJsonValue(writeTotal):QJsonValue()},
        {"download",seconds>0?QJsonValue(rxTotal):QJsonValue()},{"upload",seconds>0?QJsonValue(txTotal):QJsonValue()},
        {"processes",processes},{"skippedProcesses",skipped},{"errors",errors},{"sampleMs",double(cost.nsecsElapsed())/1e6},{"monotonicMs",double(now)/1e6}};
}
}
