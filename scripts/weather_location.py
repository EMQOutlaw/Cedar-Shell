#!/usr/bin/env python3
"""Approximate IP location and explicit city search. Never retain the public IP."""
import json,math,os,sys,time,urllib.parse,urllib.request
from pathlib import Path
from migrate import write_json,private
TTL=86400
RETRY=1800
URL='https://ipwho.is/?fields=success,city,region,country,latitude,longitude'

def request(url):
    from network_policy import require
    require('location' if url.startswith('https://ipwho.is/') else 'city-search')
    req=urllib.request.Request(url,headers={'User-Agent':'CEDAR-Shell','Accept':'application/json'})
    with urllib.request.urlopen(req,timeout=8) as response:
        data=response.read(65537)
        if len(data)>65536:raise ValueError('Location response was too large.')
        return json.loads(data)

def coordinates(lat,lon):
    if isinstance(lat,bool) or isinstance(lon,bool):raise ValueError('Invalid coordinates.')
    lat,lon=float(lat),float(lon)
    if not math.isfinite(lat) or not math.isfinite(lon) or not -90<=lat<=90 or not -180<=lon<=180:raise ValueError('Invalid coordinates.')
    return round(lat,2),round(lon,2)

def clean(value):
    return ''.join(c for c in str(value or '') if c.isprintable() and c not in '<>')[:100]

def normalize(data,search=False):
    lat,lon=coordinates(data.get('latitude'),data.get('longitude'))
    parts=[clean(data.get(k)) for k in (('name','admin1','country') if search else ('city','region','country'))]
    parts=list(dict.fromkeys(p for p in parts if p))
    if not parts:raise ValueError('No location name was returned.')
    return {'latitude':lat,'longitude':lon,'name':', '.join(parts),'source':'Open-Meteo / GeoNames' if search else 'IPWhois'}

def cache_path():return Path(os.environ.get('XDG_CACHE_HOME') or Path.home()/'.cache')/'cedar/weather-location.json'

def locate(force=False,now=None):
    now=time.time() if now is None else now
    path=cache_path()
    try:cache=json.loads(path.read_text())
    except (OSError,ValueError):cache={}
    location=cache.get('location')
    try:
        if location:
            lat,lon=coordinates(location['latitude'],location['longitude'])
            location={'latitude':lat,'longitude':lon,'name':clean(location['name']),'source':'IPWhois'}
    except (ValueError,KeyError,TypeError):location=None
    age=now-cache.get('updated',0)
    recent=0<=now-cache.get('attempted',0)<(60 if force else RETRY)
    if location and 0<=age<TTL and not force:return {**location,'cached':True,'stale':False}
    if recent:
        if location:return {**location,'cached':True,'stale':True}
        raise RuntimeError('Automatic location is temporarily unavailable. Retry later or choose a city.')
    cache['attempted']=now
    private(path.parent)
    write_json(path,cache)
    try:
        data=request(URL)
        if data.get('success') is not True:raise ValueError('IP location lookup failed.')
        location=normalize(data)
        write_json(path,{'location':location,'updated':now,'attempted':now})
        return {**location,'cached':False,'stale':False}
    except Exception:
        if location:return {**location,'cached':True,'stale':True}
        raise RuntimeError('Automatic location is unavailable. Check your connection or choose a city.') from None

def search(query):
    query=str(query).strip()
    if not 2<=len(query)<=100:raise ValueError('Enter a city or postal code, using 2–100 characters.')
    params=urllib.parse.urlencode({'name':query,'count':5,'language':'en','format':'json'})
    data=request('https://geocoding-api.open-meteo.com/v1/search?'+params)
    if data.get('error'):raise RuntimeError('City search is unavailable. Try again later.')
    results=[]
    for row in data.get('results',[])[:5]:
        try:results.append(normalize(row,True))
        except (TypeError,ValueError):continue
    return {'results':results}

def main(req):
    if req.get('action')=='search':return search(req.get('query',''))
    if req.get('action','locate')=='locate':return locate(req.get('force') is True)
    raise ValueError('Unknown location action.')

if __name__=='__main__':
    try:print(json.dumps({'ok':True,'data':main(json.loads(sys.stdin.readline()))}))
    except Exception as error:
        message=str(error) if isinstance(error,(ValueError,RuntimeError)) else 'Location service unavailable. Try again later.'
        print(json.dumps({'ok':False,'error':message}))
