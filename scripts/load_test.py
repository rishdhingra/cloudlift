#!/usr/bin/env python3
"""Bounded read-only load: max 300 requests, max 10 concurrent workers."""
import argparse, concurrent.futures, json, time, urllib.request
p=argparse.ArgumentParser(); p.add_argument('url'); p.add_argument('--requests',type=int,default=100); p.add_argument('--workers',type=int,default=5)
a=p.parse_args()
if not 1<=a.requests<=300 or not 1<=a.workers<=10: p.error('Limit: 300 requests and 10 workers')
def hit(_):
    start=time.monotonic()
    try:
        with urllib.request.urlopen(a.url.rstrip('/')+'/health',timeout=10) as r: ok=r.status==200
    except Exception: ok=False
    return ok, (time.monotonic()-start)*1000
start=time.monotonic()
with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as ex: results=list(ex.map(hit,range(a.requests)))
lat=sorted(t for _,t in results)
print(json.dumps({'requests':len(results),'concurrency':a.workers,'successes':sum(ok for ok,_ in results),'failures':sum(not ok for ok,_ in results),'p50_ms':round(lat[int((len(lat)-1)*.50)],2),'p95_ms':round(lat[int((len(lat)-1)*.95)],2),'elapsed_seconds':round(time.monotonic()-start,2)},indent=2))
raise SystemExit(any(not ok for ok,_ in results))
