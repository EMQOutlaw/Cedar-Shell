.pragma library

// Pure activity policy. Display components never decide which event wins.
var priorities = {passive:0,normal:1,high:2,critical:3};
var icons = {volume:"󰕾",brightness:"󰃟",media:"♫",notification:"󰂚",bluetooth:"󰂯",network:"󰖩",vpn:"󰌾",recording:"●",microphone:"󰍬",camera:"󰄀",power:"ϟ",workspace:"▣",keyboard:"⇪",timer:"◷",clipboard:"✓",screenshot:"▧",file:"▤",update:"↑",warning:"!",progress:"↓",integration:"◈"};
function create() { return {rows:[],history:[],sequence:0}; }
function clean(value,max) { return String(value ?? "").replace(/[\u0000-\u0008\u000b-\u001f]/g,"").slice(0,max); }
function historyEntry(row,now) { return {id:row.id,type:row.type,title:row.title,subtitle:row.subtitle,icon:row.icon,timestamp:now,source:row.source}; }
function archive(state,rows,now) {
    var history=state.history.slice();
    rows.filter(r=>r.remember && !["notification","microphone","camera","clipboard"].includes(r.type)).forEach(r=>history.unshift(historyEntry(r,now)));
    return history.slice(0,32);
}
function publish(state,event,now) {
    if (!event || !event.id || !(event.type in icons)) throw new Error("An activity needs an id and a supported type.");
    var old=state.rows.find(r=>r.id===event.id);
    var priority=typeof event.priority==="number" ? event.priority:priorities[event.priority || "normal"];
    if (![0,1,2,3].includes(priority)) throw new Error("Invalid activity priority.");
    var timeout=Math.max(800,Math.min(60000,Number(event.timeout ?? 4000)));
    if (!isFinite(timeout)) throw new Error("Invalid activity duration.");
    var announce=event.announce===true || (!old && event.announce!==false);
    var row={id:clean(event.id,160),type:event.type,source:clean(event.source || "cedar",80),priority:priority,
        title:clean(event.title,180),subtitle:clean(event.subtitle,420),icon:icons[event.type],
        progress:typeof event.progress==="number" && isFinite(event.progress) ? Math.max(0,Math.min(1,event.progress)):-1,
        persistent:!!event.persistent,sticky:!!event.sticky,remember:!!event.remember,timeout:timeout,
        timestamp:old?.timestamp ?? now,updated:now,sequence:old?.sequence ?? state.sequence+1,
        attentionUntil:announce ? now+Math.min(timeout,6000):old?.attentionUntil ?? 0,
        expiresAt:event.leaseMs ? now+Math.min(60000,Math.max(1000,event.leaseMs)):event.persistent ? 0:now+timeout,
        actions:(event.actions || []).slice(0,6).map(a=>({id:clean(a.id,80),label:clean(a.label,50)})),
        data:event.data || {}};
    var rows=state.rows.filter(r=>r.id!==row.id),evicted=[];
    if(rows.length>=64){
        var candidates=rows.filter(r=>!r.persistent).sort((a,b)=>a.priority-b.priority || a.updated-b.updated);
        if(!candidates.length)throw new Error("The activity stack is full.");
        evicted=[candidates[0]];rows=rows.filter(r=>r.id!==candidates[0].id);
    }
    rows.push(row);
    return {rows:rows,history:archive(state,(old && old.remember && old.title!==row.title ? [old]:[]).concat(evicted),now),sequence:old ? state.sequence:state.sequence+1};
}
function remove(state,id,now,remember) {
    return {rows:state.rows.filter(r=>r.id!==id),history:remember===false ? state.history:archive(state,state.rows.filter(r=>r.id===id),now),sequence:state.sequence};
}
function expire(state,now,heldId) {
    var expired=state.rows.filter(r=>r.id!==heldId && r.expiresAt>0 && r.expiresAt<=now);
    if(!expired.length)return state;
    return {rows:state.rows.filter(r=>!expired.includes(r)),history:archive(state,expired,now),sequence:state.sequence};
}
function priority(row,now,heldId) { return row.sticky || row.id===heldId || row.attentionUntil>now || !row.persistent ? row.priority:0; }
function ranked(state,now,heldId) {
    return state.rows.slice().sort((a,b)=>priority(b,now,heldId)-priority(a,now,heldId) || (b.id===heldId ? 1:0)-(a.id===heldId ? 1:0) || b.attentionUntil-a.attentionUntil || a.sequence-b.sequence);
}
function foreground(state,now,heldId,selectedId) {
    var rows=ranked(state,now,heldId),selected=rows.find(r=>r.id===selectedId);
    if(selected && !(rows[0]?.sticky && rows[0].priority===3))return selected;
    return rows[0] || null;
}
function external(event,now) {
    if(!event || !/^[a-z0-9][a-z0-9._-]{0,39}$/.test(event.source || "") || !/^[a-z0-9][a-z0-9._-]{0,59}$/.test(event.id || ""))throw new Error("Use a short source and id made of lowercase letters, digits, dots or hyphens.");
    if(!["progress","update","integration"].includes(event.type))throw new Error("External publishers support progress, update, or integration activities.");
    // Providers supply data, never executable actions or trusted privacy/recording claims.
    const text=(value,limit)=>String(value ?? "").replace(/[\u0000-\u001f]/g," ").slice(0,limit);
    return {id:"external/"+event.source+"/"+event.id,type:event.type,source:event.source,title:text(event.title,160),subtitle:text(event.subtitle,240),
        priority:event.priority==="high" ? "high":"normal",progress:event.progress,persistent:!!event.persistent,
        leaseMs:event.persistent ? Math.min(60000,Math.max(1000,Number(event.leaseMs)||30000)):0,
        timeout:Number(event.timeout)||5000,announce:event.announce,remember:!!event.remember,actions:[]};
}
