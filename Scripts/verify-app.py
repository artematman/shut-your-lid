import pathlib,plistlib,subprocess,sys,json
app=pathlib.Path(sys.argv[1]);c=app/'Contents'
p=plistlib.loads((c/'Info.plist').read_bytes());identity='com.artemkharitonov.shutyourlid'
assert p['CFBundleIdentifier']==identity and p['LSUIElement']
d=plistlib.loads((c/'Library/LaunchDaemons'/f'{identity}.power.plist').read_bytes())
assert d['Label']==identity+'.power' and d['MachServices']=={identity+'.power':True}
assert d['BundleProgram']=='Contents/MacOS/LidPowerHelper'
assert d['AssociatedBundleIdentifiers']==[identity]
# Launch constraint: launchd (macOS 14+) must refuse anything but this Developer ID helper.
team='8XZ7Z4UR6C'
assert d.get('SpawnConstraint')=={'team-identifier':team,'signing-identifier':identity+'.power','validation-category':6}, 'helper SpawnConstraint missing or wrong'
helper_info=subprocess.run(['codesign','-dv',str(c/'MacOS/LidPowerHelper')],capture_output=True,text=True).stderr
assert f'Identifier={identity}.power' in helper_info.splitlines() and f'TeamIdentifier={team}' in helper_info.splitlines(), 'helper signature does not match its SpawnConstraint'
# validation-category 6 = Developer ID: leaf carries the Developer ID Application OID, intermediate the Developer ID CA OID.
developer_id=f'anchor apple generic and identifier "{identity}.power" and certificate leaf[subject.OU] = "{team}" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate 1[field.1.2.840.113635.100.6.2.6] exists'
subprocess.run(['codesign','--verify','-R','='+developer_id,str(c/'MacOS/LidPowerHelper')],check=True)
assert p['CFBundleIconFile'] == 'ShutYourLidLips.icns'
assert (c/'Resources'/p['CFBundleIconFile']).stat().st_size>1000
for path,bundle_id in [(app,identity),(c/'MacOS/LidPowerHelper',identity+'.power')]:
 subprocess.run(['codesign','--verify','--strict',str(path)],check=True)
 requirement=f'anchor apple generic and identifier "{bundle_id}" and certificate leaf[subject.OU] = "8XZ7Z4UR6C"'
 subprocess.run(['codesign','--verify','-R','='+requirement,str(path)],check=True)
 for executable in [c/'MacOS/ShutYourLid',c/'MacOS/LidPowerHelper']:
  deps=[line for line in subprocess.check_output(['otool','-L',str(executable)],text=True).splitlines() if line.startswith('\t')]
  assert set(subprocess.check_output(['lipo','-archs',str(executable)],text=True).split())=={'arm64','x86_64'}, 'universal binary required'
  assert not any('/Users/' in line or '/private/tmp/' in line for line in deps)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(json.dumps({'bundle':identity,'version':p['CFBundleShortVersionString'],'signature':'Developer ID verified','helper':'own daemon and Mach service verified'},indent=2))

subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("privacy-gate.py")), "--app", str(app)], check=True)
