#!/usr/bin/env python3
"""CEDAR application appearance service: JSON request on stdin, JSON response on stdout."""
import json
import sys
from theming import engine, registry
from theming.transaction import Store

def public_plan(plan):
    return {'id':plan['id'],'theme':plan['theme'],'reports':plan['reports'],
            'changes':[{'application':o['app'],'path':o['path'],'kind':o['kind']} for o in plan['operations'] if o['before']!=o['after']]}

def dispatch(request,store=None):
    store=store or Store();action=request.get('action','status')
    if action=='status':return engine.status(store)
    if action=='preview':return public_plan(engine.preview(store,request.get('options')))
    if action=='apply':return engine.apply(store,request['options'],request['previewId'])
    if action=='sync':return engine.synchronize(store)
    if action in ('restore','reset'):
        owners=store.json(store.state/'ownership.json',{})
        affected={o['app'] for o in (owners.values() if action=='reset' else store.json(store.state/'last.json',{}).get('operations',[]))}
        store.save(store.state/'status.json',{'paused':True,'reports':[],'note':'Automatic synchronization paused for restoration.'})
        result=store.restore(reset=action=='reset')
        reports=engine.reload_apps([{'id':id,'status':'Ready','reload':registry.REGISTRY[id]['reload']} for id in affected if id in registry.REGISTRY])
        for row in reports:row['status']='Restored'
        store.save(store.state/'status.json',{'paused':True,'reports':reports,'changed':result['changed'],'note':'Previous configuration restored. Automatic synchronization is paused until Apply.'})
        return result
    if action=='recover':
        with store.lock():store.recover()
        return {'recovered':True}
    raise ValueError('Unknown theming action.')

def main():
    try:
        raw=sys.stdin.buffer.readline(1024*1024+1)
        if len(raw)>1024*1024:raise ValueError('Request exceeds 1 MiB.')
        request=json.loads(raw)
        if not isinstance(request,dict):raise ValueError('Expected an object.')
        result=dispatch(request);response={'ok':True,'data':result}
    except Exception as error:
        response={'ok':False,'error':str(error)}
    print(json.dumps(response))
if __name__=='__main__':main()
