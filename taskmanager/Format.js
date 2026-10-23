.pragma library
function known(v) { return v !== undefined && v !== null && isFinite(Number(v)); }
function percent(v) { return known(v) ? Number(v).toFixed(1) + "%" : "—"; }
function bytes(v) { if (!known(v)) return "—"; const u=["B","KiB","MiB","GiB","TiB"]; let n=Number(v),i=0; while(n>=1024 && i<4){n/=1024;i++;} return n.toFixed(i ? 1 : 0)+" "+u[i]; }
function rate(v) { return known(v) ? bytes(v)+"/s" : "—"; }
function optional(v,suffix) { return known(v) ? Number(v).toFixed(0)+suffix : "—"; }
function runtime(v) { if(!known(v)) return "—"; const n=Math.floor(v); return n>=3600 ? Math.floor(n/3600)+"h "+Math.floor(n%3600/60)+"m" : Math.floor(n/60)+"m "+n%60+"s"; }
function state(s) { return ({R:"Running",S:"Sleeping",D:"Waiting",T:"Suspended",t:"Tracing",Z:"Zombie",I:"Idle"})[s] || s || "Unknown"; }
