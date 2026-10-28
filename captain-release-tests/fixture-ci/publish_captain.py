"""Publish a verified, signed APK under an immutable version URL, then advance update metadata."""
import argparse,hashlib,json,os,pathlib,re,subprocess,tempfile
REPO='Fazaa-Sat7a/fazaa-sat7a'
def manifest(code,apk,version):
    if not 1001<=code<=2100000000:raise ValueError('Invalid release code')
    return {'packageId':'com.fazaa.driver.test','versionCode':code,'versionName':version,'apkUrl':f'https://github.com/{REPO}/releases/download/captain-v{code}/fazaa-captain.apk','sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'notes':'تحسين حالة استقبال الطلبات باللون الأخضر وتصحيح فحص التحديثات. يترافق الإصدار مع إصلاح اكتشاف الطلبات في قاعدة البيانات.'}
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--version-code',type=int,required=True);parser.add_argument('--apk',type=pathlib.Path,required=True);args=parser.parse_args()
    if os.environ.get('GITHUB_REPOSITORY')!=REPO:raise RuntimeError('Unexpected repository')
    if not args.apk.is_file() or args.apk.stat().st_size<1000:raise RuntimeError('Missing verified APK')
    gradle=pathlib.Path('android/app/build.gradle').read_text();match=re.search(r"versionName\s+'([0-9][A-Za-z0-9.+-]{0,39})'",gradle)
    if not match:raise RuntimeError('Missing release version name')
    data=manifest(args.version_code,args.apk,match.group(1));tag=f'captain-v{args.version_code}'
    def gh(*params,check=True):return subprocess.run(['gh',*params,'--repo',REPO],check=check,capture_output=True,text=True)
    # An existing version is never overwritten: a re-run cannot silently change a versioned download.
    existing=gh('release','view',tag,check=False)
    if existing.returncode==0:raise RuntimeError('This version already exists. Start a NEW workflow run for a newer version code.')
    with tempfile.TemporaryDirectory(prefix='captain-publish-') as folder:
        folder=pathlib.Path(folder);apk=folder/'fazaa-captain.apk';apk.write_bytes(args.apk.read_bytes())
        notes=folder/'notes.txt';notes.write_text(data['notes']+'\nCommit: '+os.environ['GITHUB_SHA']+'\nSHA256: '+data['sha256'],encoding='utf-8')
        gh('release','create',tag,str(apk),'--target',os.environ['GITHUB_SHA'],'--title',f"Fazaa Captain {data['versionName']} ({args.version_code})",'--notes-file',str(notes),'--prerelease')
        channel=gh('release','view','captain-updates',check=False)
        if channel.returncode!=0:
            gh('release','create','captain-updates','--target',os.environ['GITHUB_SHA'],'--title','Fazaa Captain update channel','--notes','Update metadata for the Captain app. Versioned APKs are in separate releases.','--prerelease')
        metadata=folder/'update.json';metadata.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        gh('release','upload','captain-updates',str(metadata),'--clobber')
    print('Published versioned APK and Captain update manifest.')
if __name__=='__main__':main()
