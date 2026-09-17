#!/usr/bin/env python3
"""Run the one-off RDS migration task. Requires deployed infrastructure."""
import json,subprocess,time,pathlib,os
os.environ.setdefault('AWS_PROFILE','cloudlift'); os.environ.setdefault('AWS_REGION','us-east-1')
root=pathlib.Path(__file__).resolve().parents[1]
def aws(*args): return json.loads(subprocess.check_output(['aws',*args,'--output','json'],text=True))
demo=json.loads(subprocess.check_output(['terraform','-chdir='+str(root/'terraform'),'output','-json','demo'],text=True))
response=aws('ecs','run-task','--cluster',demo['cluster'],'--task-definition',demo['migration_task'],'--launch-type','FARGATE','--network-configuration',json.dumps({'awsvpcConfiguration':{'subnets':demo['subnets'],'securityGroups':[demo['security_group']],'assignPublicIp':'ENABLED'}}))
assert not response.get('failures'),response.get('failures')
task=response['tasks'][0]['taskArn']
for _ in range(90):
 t=aws('ecs','describe-tasks','--cluster',demo['cluster'],'--tasks',task)['tasks'][0]
 if t['lastStatus']=='STOPPED':
  assert all(c.get('exitCode')==0 for c in t['containers']),t.get('stoppedReason')
  print('Migration succeeded.'); break
 time.sleep(5)
else:
 aws('ecs','stop-task','--cluster',demo['cluster'],'--task',task,'--reason','Migration timeout')
 raise SystemExit('Migration exceeded 7.5 minutes; inspect CloudWatch and clean up')
