import QtQuick
import Quickshell
import Quickshell.Services.Notifications as Notifications
import ".."
import "../services"

Scope {
    Notifications.NotificationServer {
        id: server
        keepOnReload: false
        extraHints:["image-path"]
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        persistenceSupported: false
        onNotification: n => {
            n.tracked = true;
            NoticeStore.record(n);
        }
    }
    Variants {
        model: server.trackedNotifications.values
        Scope {
            id: lifetime
            required property var modelData
            readonly property int noticeId: modelData.id
            Connections {
                target: lifetime.modelData
                function onClosed(reason) { NoticeStore.forget(lifetime.noticeId); }
            }
            Timer {
                interval: lifetime.modelData.expireTimeout > 0 ? lifetime.modelData.expireTimeout : Math.max(3,Config.saved.notificationSeconds)*1000
                running: lifetime.modelData.expireTimeout !== 0 && lifetime.modelData.urgency !== Notifications.NotificationUrgency.Critical
                onTriggered: lifetime.modelData.expire()
            }
        }
    }
}
