import importlib.util,json,os,pathlib,sys,tempfile,unittest.mock as mock
source=pathlib.Path(__file__).parent/'fixture-ci/publish_admin.py'
spec=importlib.util.spec_from_file_location('publish',source);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as folder:
    previous=os.getcwd();os.chdir(folder)
    try:
        apk=pathlib.Path('signed.apk');apk.write_bytes(b'fixture-only'*1000)
        gradle=pathlib.Path('android-admin/app/build.gradle');gradle.parent.mkdir(parents=True);gradle.write_text("versionName '0.1.1'")
        calls=[];metadata=[]
        def run(command,**kwargs):
            calls.append(command)
            if command[1:3]==['release','upload']:
                data=json.loads(pathlib.Path(command[4]).read_text());metadata.append(data)
            return type('Result',(),{'returncode':1 if command[1:3]==['release','view'] else 0})()
        with mock.patch.dict(os.environ,{'GITHUB_REPOSITORY':module.REPO,'GITHUB_SHA':'a'*40}),mock.patch.object(sys,'argv',['publish','--version-code','1012','--apk',str(apk.resolve())]),mock.patch.object(module.subprocess,'run',run):module.main()
        assert metadata[0]['versionCode']==1012 and metadata[0]['versionName']=='0.1.1'
        assert metadata[0]['apkUrl'].endswith('/admin-v1012/fazaa-admin.apk')
        assert calls[1][1:4]==['release','create','admin-v1012'] and calls[-1][1:4]==['release','upload','admin-updates']
        with mock.patch.dict(os.environ,{'GITHUB_REPOSITORY':module.REPO,'GITHUB_SHA':'a'*40}),mock.patch.object(sys,'argv',['publish','--version-code','1012','--apk',str(apk.resolve())]),mock.patch.object(module.subprocess,'run',return_value=type('Result',(),{'returncode':0})()):
            try:module.main();raise AssertionError('Existing release overwritten')
            except RuntimeError as e:assert 'already exists' in str(e)
    finally:os.chdir(previous)
print('PASS immutable release, APK-before-manifest publishing, automatic version name and rerun protection')
