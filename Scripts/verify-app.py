import pathlib,plistlib,subprocess,sys,json
app=pathlib.Path(sys.argv[1]);c=app/'Contents'
p=plistlib.loads((c/'Info.plist').read_bytes());identity='com.artemkharitonov.shutyourlid'
assert p['CFBundleIdentifier']==identity and p['LSUIElement']
d=plistlib.loads((c/'Library/LaunchDaemons'/f'{identity}.power.plist').read_bytes())
assert d['Label']==identity+'.power' and d['MachServices']=={identity+'.power':True}
assert d['BundleProgram']=='Contents/MacOS/LidPowerHelper'
assert d['AssociatedBundleIdentifiers']==[identity]
assert (c/'Resources/AppIcon.icns').stat().st_size>1000
for path,bundle_id in [(app,identity),(c/'MacOS/LidPowerHelper',identity+'.power')]:
 subprocess.run(['codesign','--verify','--strict',str(path)],check=True)
 requirement=f'anchor apple generic and identifier "{bundle_id}" and certificate leaf[subject.OU] = "8XZ7Z4UR6C"'
 subprocess.run(['codesign','--verify','-R','='+requirement,str(path)],check=True)
 for executable in [c/'MacOS/ShutYourLid',c/'MacOS/LidPowerHelper']:
  deps=subprocess.check_output(['otool','-L',str(executable)],text=True).splitlines()[1:]
  assert not any('/Users/' in line or '/private/tmp/' in line for line in deps)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(json.dumps({'bundle':identity,'version':p['CFBundleShortVersionString'],'signature':'Developer ID verified','helper':'own daemon and Mach service verified'},indent=2))

subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("privacy-gate.py")), "--app", str(app)], check=True)
