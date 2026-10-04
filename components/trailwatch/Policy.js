.pragma library

// NOAA fractional-year approximation. Civil twilight = solar elevation -6°.
// Returns instants, never fake local readings; polar crossings remain null.
function solar(date, latitude, longitude) {
    if (String(latitude).trim() === "" || String(longitude).trim() === "") return null;
    const lat = Number(latitude), lon = Number(longitude);
    if (!isFinite(lat) || !isFinite(lon) || Math.abs(lat)>90 || Math.abs(lon)>180) return null;
    // Use the location's mean-solar date, not the computer's calendar date.
    // Otherwise a remote location across the date line can show night at noon.
    const localSolar=new Date(date.getTime()+lon*240000);
    const year=localSolar.getUTCFullYear(), month=localSolar.getUTCMonth(), day=localSolar.getUTCDate();
    const midnight=Date.UTC(year,month,day), doy=(midnight-Date.UTC(year,0,1))/86400000+1;
    const leap=(year%4===0 && (year%100!==0 || year%400===0)), g=2*Math.PI/(leap?366:365)*(doy-1);
    const eq=229.18*(.000075+.001868*Math.cos(g)-.032077*Math.sin(g)-.014615*Math.cos(2*g)-.040849*Math.sin(2*g));
    const dec=.006918-.399912*Math.cos(g)+.070257*Math.sin(g)-.006758*Math.cos(2*g)+.000907*Math.sin(2*g)-.002697*Math.cos(3*g)+.00148*Math.sin(3*g);
    const noon=midnight+(720-4*lon-eq)*60000, rad=lat*Math.PI/180;
    function span(zenith) {
        const cos=(Math.cos(zenith*Math.PI/180)-Math.sin(rad)*Math.sin(dec))/(Math.cos(rad)*Math.cos(dec));
        return Math.abs(cos)<=1 ? Math.acos(cos)*180/Math.PI*240000 : null;
    }
    const daylight=span(90.833), twilight=span(96);
    return {noon:noon,sunrise:daylight===null?null:noon-daylight,sunset:daylight===null?null:noon+daylight,
        dawn:twilight===null?null:noon-twilight,dusk:twilight===null?null:noon+twilight};
}
function readiness(s) {
    if (s.lowPower) return {label:"LOW POWER",reason:"Battery at or below 20%",warning:true};
    if (s.hot || s.disk || s.failed>0) return {label:"WATCH",reason:s.hot?"Temperature above threshold":s.disk?"Storage needs attention":"A monitored service has failed",warning:true};
    if (s.storm) return {label:"WEATHER WATCH",reason:"Thunderstorm in current forecast",warning:true};
    if (s.offline) return {label:"OFFLINE",reason:"No active network connection",warning:true};
    if (!s.known) return {label:"CHECKING",reason:"Waiting for system readings",warning:false};
    if (s.quiet) return {label:"QUIET",reason:"Do Not Disturb is enabled",warning:false};
    return {label:"READY",reason:"No monitored threshold exceeded",warning:false};
}
function upcoming(items, now, tomorrow) {
    const start=new Date(now); start.setHours(24,0,0,0);
    return (items || []).filter(e=>Number.isFinite(e.at) && e.at >= (tomorrow?start.getTime():now))
        .sort((a,b)=>a.at-b.at)[0] || null;
}
