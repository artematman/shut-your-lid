#!/usr/bin/env python3
"""No power changes: owner-operated background continuity recorder."""
import argparse,datetime,hashlib,json,pathlib,subprocess,time
parser=argparse.ArgumentParser();parser.add_argument('mode',choices=['record','inspect']);parser.add_argument('--out',required=True,type=pathlib.Path);args=parser.parse_args()
def run(*argv): return subprocess.run(argv,capture_output=True,text=True)
if args.mode=='record':
 for label in ['local.artem.islandpro.beta.power','local.artem.islandpro.power']:
  if run('/bin/launchctl','print','system/'+label).returncode==0: raise SystemExit('Old Island daemon still registered: stop migration before testing.')
 if run('/usr/bin/pgrep','-f','/Contents/MacOS/(IslandPowerHelper|IslandPro|NotchFlowApp)').returncode==0: raise SystemExit('Old Island process still running.')
 if run('/usr/bin/pgrep','-f','/Contents/MacOS/ShutYourLid').returncode: raise SystemExit('Shut Your Lid app is not running.')
 if run('/bin/launchctl','print','system/com.artemkharitonov.shutyourlid.power').returncode: raise SystemExit('New daemon is not registered.')
 power=run('/usr/bin/pmset','-g').stdout
 if not any(line.split()[:2]==['SleepDisabled','1'] for line in power.splitlines()): raise SystemExit('Sleep-disabled mode is not active.')
 args.out.parent.mkdir(parents=True,exist_ok=True)
 with args.out.open('x') as file:
  file.write(json.dumps({'kind':'start','time':time.time(),'power':power,'instruction':'Owner must record physical lid close/open times.'})+'\n');file.flush()
  print('Recording. Close lid for at least 2 minutes; reopen, then Ctrl-C. No power settings are changed.')
  try:
   index=0
   while True:
    digest=hashlib.pbkdf2_hmac('sha256',str(index).encode(),b'Shut Your Lid continuity',10000).hex()
    file.write(json.dumps({'kind':'sample','index':index,'time':time.time(),'digest':digest})+'\n');file.flush();index+=1;time.sleep(2)
  except KeyboardInterrupt: print('Saved:',args.out)
else:
 rows=[json.loads(line) for line in args.out.read_text().splitlines()];samples=[row for row in rows if row['kind']=='sample']
 if len(samples)<2: raise SystemExit('Too few samples')
 gaps=[b['time']-a['time'] for a,b in zip(samples,samples[1:])]
 print(json.dumps({'samples':len(samples),'start':datetime.datetime.fromtimestamp(samples[0]['time']).astimezone().isoformat(),'end':datetime.datetime.fromtimestamp(samples[-1]['time']).astimezone().isoformat(),'duration_seconds':samples[-1]['time']-samples[0]['time'],'maximum_gap_seconds':max(gaps),'gaps_above_10_seconds':sum(gap>10 for gap in gaps),'hardware_acceptance':'Requires owner-confirmed close/open times covering at least 2 minutes.'},indent=2))
