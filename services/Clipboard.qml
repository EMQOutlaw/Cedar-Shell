pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"
Singleton {
    id:root
    property var items:[]
    property string error:""
    property int sequence:0
    function accept(item){
        if(!Config.saved.clipboardHistory || ShellState.locked || !["text","image"].includes(item.kind))return;
        if(items.some(i=>i.payload===item.payload))return;
        const pinned=items.filter(i=>i.pinned), recent=items.filter(i=>!i.pinned);
        items=pinned.concat([Object.assign({},item,{id:++sequence,at:Date.now(),pinned:false})],recent).slice(0,20);
    }
    function remove(id){items=items.filter(i=>i.id!==id);}
    function clear(){items=[];}
    function pin(id){if(items.filter(i=>i.pinned).length>=5 && !items.find(i=>i.id===id)?.pinned)return;items=items.map(i=>i.id===id?Object.assign({},i,{pinned:!i.pinned}):i);}
    function copy(item){if(!Config.testMode && !worker.running)worker.send(item);}
    Process {
        command:["wl-paste","--watch","python3",Quickshell.shellPath("scripts/clipboard_item.py"),"--capture"]
        running:Config.saved.clipboardHistory && !ShellState.locked && !Config.testMode
        stdout:SplitParser {onRead:data=>{try{root.accept(JSON.parse(data));}catch(_){}}}
        onExited:(code,status)=>{if(code!==0)root.error="Clipboard capture is unavailable in this session.";}
    }
    ServiceRequest {id:worker;script:"scripts/clipboard_item.py";onFailed:message=>root.error=message}
    Connections {target:ShellState;function onLockedChanged(){if(ShellState.locked)root.clear();}}
    Connections {target:Config.saved;function onClipboardHistoryChanged(){if(!Config.saved.clipboardHistory)root.clear();root.error="";}}
}
