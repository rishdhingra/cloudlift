#!/usr/bin/env python3
"""Synthetic API integration checks; no real customer data."""
import json, sys, time, urllib.request, urllib.error, uuid
base = sys.argv[1].rstrip('/')
def request(path, data=None):
    req = urllib.request.Request(base+path, data=None if data is None else json.dumps(data).encode(), headers={'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return r.status,json.load(r)
    except urllib.error.HTTPError as e: return e.code,json.load(e)
for _ in range(60):
    try:
        if request('/health')[0]==200: break
    except Exception: pass
    time.sleep(1)
else: raise SystemExit('API did not become healthy')
assert request('/')[1]['service']=='CloudLift API'
assert request('/health')[1]['database']=='connected'
assert request('/api/customers',{})[0]==400
assert request('/api/customers',{'name':'x','email':'invalid'})[0]==400
assert request('/api/customers',{'name':{'bad':'type'},'email':'x@example.invalid'})[0]==400
record={'name':'Synthetic Demo','email':str(uuid.uuid4())+'@example.invalid'}
status,created=request('/api/customers',record)
assert status==201 and created['email']==record['email']
assert request('/api/customers',record)[0]==409
assert request('/api/customers')[0]==200
assert request('/api/stats')[1]['customer_count']>=1
print(json.dumps({'result':'passed','checks':9,'synthetic_customer_id':created['id']}))
