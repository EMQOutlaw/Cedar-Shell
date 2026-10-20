#include "collector.h"
#include <sys/socket.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/prctl.h>
#include <signal.h>
#include <iostream>
using namespace CedarTask;
static void check(bool value,const char *message){if(!value){std::cerr<<"FAIL: "<<message<<'\n';exit(1);}}
int main(int argc,char **argv){QCoreApplication app(argc,argv);
    auto before=parseCpu("cpu 100 20 30 400 50 2 3 5 80 10");auto after=parseCpu("cpu 150 20 50 420 60 2 3 5 120 20");
    check(before&&before->total==610&&before->idle==450,"exclude guest double counting");
    check(cpuUsage(*after,before).toDouble()==70,"CPU tick deltas");check(cpuUsage(*before,{}).isNull(),"first sample unknown");check(cpuUsage(*before,after).isNull(),"counter rollback unknown");check(!parseCpu("cpu invalid 1 2 3"),"bad CPU fields");
    auto memory=parseMemory("MemTotal: 1000 kB\nMemAvailable: 600 kB\nCached: 100 kB\nSReclaimable: 20 kB\nBuffers: 10 kB\nSwapTotal: 500 kB\nSwapFree: 400 kB\n");
    check(memory["used"].toDouble()==400*1024&&memory["percent"].toDouble()==40,"available memory accounting");check(memory["cache"].toDouble()==120*1024,"reclaimable cache");check(memory["swapUsed"].toDouble()==100*1024,"swap");check(parseMemory("").contains("error"),"missing memory");
    auto process=parseProcess("123 (name with ) strange 雨) S 2 123 7 0 0 0 0 0 0 0 11 7 0 0 20 5 3 0 99 4000 6\n",4096);
    check(process["name"].toString()=="name with ) strange 雨","process name parentheses and spaces");check(process["start"].toString()=="99"&&process["ticks"].toString()=="18","process fields");check(process["rss"].toDouble()==24576&&process["nice"].toInt()==5,"RSS and nice");check(parseProcess("2 (broken) S 0",4096).isEmpty(),"malformed stat");check(inspectProcess(2147483647).isEmpty(),"disappeared process");
    int sockets[2];check(!socketpair(AF_UNIX,SOCK_STREAM,0,sockets),"socket pair");if(!sameUserPeer(sockets[0]))std::cout<<"SKIP: SO_PEERCRED is blocked in this execution environment\n";close(sockets[0]);close(sockets[1]);check(!sameUserPeer(-1),"invalid peer denied");
    QJsonObject target{{"pid",9999},{"session",3},{"sameUser",true},{"exe","/usr/bin/sleep"}};
    check(protectedReason(target,{}).isEmpty(),"ordinary process eligible");target["sameUser"]=false;check(!protectedReason(target,{}).isEmpty(),"foreign user protected");target["sameUser"]=true;check(!protectedReason(target,{9999}).isEmpty(),"ancestor protected");target["cgroup"]="0::/user.slice/session.slice/essential.service";check(!protectedReason(target,{}).isEmpty(),"session cgroup protected");
    GpuCollector absentGpu("/cedar-test-missing-nvml.so");QHash<qint64,quint64> gpuProcesses;QString gpuStatus;check(absentGpu.sample(gpuProcesses,gpuStatus).isEmpty()&&!gpuStatus.isEmpty(),"missing NVML is explicit and safe");
    QTemporaryDir fixture;QDir root(fixture.path());root.mkpath("proc/self");root.mkpath("sys");auto write=[&](QString path,QByteArray value){QFile f(root.filePath(path));check(f.open(QIODevice::WriteOnly),"fixture open");f.write(value);};
    write("proc/stat","cpu 10 0 10 80 0 0 0 0\ncpu0 10 0 10 80 0 0 0 0\n");write("proc/meminfo","MemTotal: 100 kB\nMemAvailable: 40 kB\n");write("proc/uptime","10 0\n");write("proc/loadavg","0.1 0.2 0.3 1/1 1\n");
    Collector c(root.filePath("proc"),root.filePath("sys"));auto first=c.sample();check(first["cpu"].toObject()["percent"].isNull(),"collector initial baseline");check(first["cpu"].toObject()["temperature"].isNull(),"missing temperature stays unknown");check(first["processes"].toArray().isEmpty(),"empty proc safe");
    write("proc/stat","cpu 20 0 20 80 0 0 0 0\ncpu0 20 0 20 80 0 0 0 0\n");check(c.sample()["cpu"].toObject()["percent"].toDouble()==100,"collector consecutive samples");
    pid_t child=fork();if(child==0){prctl(PR_SET_PTRACER,PR_SET_PTRACER_ANY);execl("/usr/bin/sleep","sleep","30",nullptr);_exit(1);}
    check(child>0,"disposable process creation");QThread::msleep(50);auto targetProcess=inspectProcess(child);
    QJsonObject request{{"pid",qint64(child)},{"start",targetProcess["start"]},{"action","stop"}};
    auto stopped=processAction(request,{});
    if(stopped["ok"].toBool()){
        QThread::msleep(30);check(inspectProcess(child)["state"]=="T","SIGSTOP delivered");
        request["action"]="continue";check(processAction(request,{})["ok"].toBool(),"SIGCONT delivered");
        request["action"]="nice";request["nice"]=10;auto priority=processAction(request,{});check(priority["ok"].toBool()||priority["code"]=="denied","guarded priority or explicit tracing denial");
        request["action"]="kill";check(processAction(request,{})["code"]=="confirmation","kill requires consent");
        request["confirmed"]=true;request["start"]="0";check(processAction(request,{})["code"]=="identity","PID reuse guard");
        request["start"]=targetProcess["start"];check(processAction(request,{})["ok"].toBool(),"pidfd SIGKILL");
        int status=0;waitpid(child,&status,0);check(WIFSIGNALED(status)&&WTERMSIG(status)==SIGKILL,"child exited");
        check(processAction(request,{})["code"]=="exited","exited process refusal");
        std::cout<<"PASS: real pidfd stop/resume/kill, priority safety, confirmation and identity checks\n";
    }else{kill(child,SIGKILL);waitpid(child,nullptr,0);std::cout<<"SKIP: process kernel calls blocked: "<<stopped["message"].toString().toStdString()<<'\n';}
    std::cout<<"PASS: collector accounting, parsing, reset, disappearing entries, peer and protection checks\n";
}
