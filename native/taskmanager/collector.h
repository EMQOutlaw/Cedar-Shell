#pragma once
#include <QtCore>
#include <optional>

namespace CedarTask {
constexpr int Protocol = 1;
QByteArray readFile(const QString &path, qint64 limit = 1024 * 1024);
struct CpuTimes { quint64 total=0, idle=0; };
std::optional<CpuTimes> parseCpu(const QByteArray &line);
QJsonValue cpuUsage(CpuTimes now, std::optional<CpuTimes> before);
QJsonObject parseMemory(const QByteArray &text);
QJsonObject parseProcess(const QByteArray &stat, qint64 pageSize);
QString runtimeDirectory();
bool sameUserPeer(qintptr fd, qint64 *pid = nullptr);
QString protectedReason(const QJsonObject &process, const QSet<qint64> &protectedPids);
QJsonObject processAction(const QJsonObject &request, const QSet<qint64> &protectedPids);
QJsonObject inspectProcess(qint64 pid, const QString &procRoot = "/proc");

class GpuCollector {
    QLibrary library;
    bool initialized=false;
public:
    explicit GpuCollector(QString libraryName="libnvidia-ml.so.1");
    ~GpuCollector();
    QJsonArray sample(QHash<qint64,quint64> &processMemory, QString &status);
};
class Collector {
    QString proc, sys;
    QHash<QString,CpuTimes> cpuBefore;
    QHash<QString,quint64> ticksBefore;
    QHash<QString,QPair<quint64,quint64>> ioBefore, netBefore;
    QElapsedTimer elapsed;
    qint64 previousNs=0;
    QString cpuModel;
    QStringList temperaturePaths;
    QHash<uint,QString> owners;
    GpuCollector gpu;
public:
    explicit Collector(QString procRoot="/proc", QString sysRoot="/sys");
    QJsonObject sample();
};
}
