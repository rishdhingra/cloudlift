#!/usr/bin/env python3
"""Prepare local inputs; does not deploy. Requires an updated amd64 image digest."""
import argparse,datetime,ipaddress,json,pathlib,re
p=argparse.ArgumentParser(); p.add_argument('--image',required=True); p.add_argument('--client-ip',required=True); p.add_argument('--existing-oidc-provider',default='')
a=p.parse_args()
if not re.fullmatch(r'public\.ecr\.aws/c5t6h8t1/cloudlift-api@sha256:[a-f0-9]{64}',a.image): p.error('Use this project repository and an immutable image digest')
ip=ipaddress.IPv4Address(a.client_ip)
now=datetime.datetime.now(datetime.timezone.utc)
deadline=(now+datetime.timedelta(hours=4)).strftime('%Y-%m-%dT%H:%M:%SZ')
config={'container_image':a.image,'allowed_http_cidrs':[str(ip)+'/32'],'desired_count':0,'cleanup_at':deadline,'existing_github_oidc_provider_arn':a.existing_oidc_provider}
root=pathlib.Path(__file__).resolve().parents[1]
(root/'terraform/demo.auto.tfvars.json').write_text(json.dumps(config,indent=2)+'\n')
print('Prepared local inputs, no deployment. Cleanup deadline:',deadline)
