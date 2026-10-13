from pathlib import Path
import json,shutil
root=Path(__file__).resolve().parents[1]
source=root/'macos/HankyeonSafariExtension/Resources'
for browser in ['chromium','firefox']:
    dest=root/'extensions'/browser; dest.mkdir(exist_ok=True)
    shutil.copytree(source/'media',dest/'media',dirs_exist_ok=True)
    shutil.copy(root/'extensions/browser/background.js',dest/'background.js')
    for f in ['options.html','options.js']: shutil.copy(root/'extensions/browser'/f,dest/f)
    manifest={'manifest_version':3,'name':'Hankyeon Media Connector','version':'0.1.0','permissions':['scripting','tabs','storage'],'host_permissions':['http://*/*','https://*/*'],'options_ui':{'page':'options.html','open_in_tab':True},'content_scripts':[{'matches':['http://*/*','https://*/*'],'js':['media/media-observer.js'],'all_frames':True,'match_about_blank':True,'run_at':'document_idle'}]}
    if browser=='chromium':
        manifest['background']={'service_worker':'background.js','type':'module'}
        manifest['minimum_chrome_version']='116'
    else:
        manifest['background']={'scripts':['background.js'],'type':'module'}
        manifest['browser_specific_settings']={'gecko':{'id':'hankyeon-media@jameslee.local','strict_min_version':'128.0'}}
    (dest/'manifest.json').write_text(json.dumps(manifest,indent=2))
