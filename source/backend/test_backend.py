#!/usr/bin/env python3
"""Native integration checks. Python is for development QA only, never app runtime.
Usage: test_backend.py ENGINE FRENCH_MP4 SILENT_WAV NO_AUDIO_MP4 REPORT_JSON
French fixture text is generated with macOS say -v Thomas, documented in README.
"""
import hashlib,json,pathlib,subprocess,sys,tempfile,time,signal,os,unicodedata
engine,fixture,silent,noaudio,report=map(pathlib.Path,sys.argv[1:])
engine,fixture,silent,noaudio=map(lambda p:p.resolve(),(engine,fixture,silent,noaudio))
checks=[]
def check(name,result):
    checks.append({'check':name,'passed':bool(result)})
    if not result:raise AssertionError(name)
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
original=digest(fixture)
with tempfile.TemporaryDirectory(prefix='artcraft-backend-qa-') as d:
    out=pathlib.Path(d)/'transcription.json'
    started=time.monotonic()
    p=subprocess.run([str(engine),'--input',str(fixture),'--output',str(out),'--context','Grenoble, Élodie, FilmCraft.','--lines','1','--max-duration','4'],capture_output=True,text=True,timeout=600)
    elapsed=time.monotonic()-started
    check('French video transcription completes',p.returncode==0)
    data=json.loads(out.read_text());cues=data['segments'];events=[json.loads(l) for l in p.stdout.splitlines()]
    check('Language is French',data['language']=='fr')
    check('Real large-v3 model selected',data['model']=='Whisper large-v3 Q5_0')
    check('Several editable cues',len(cues)>=4)
    check('All cues inside source duration',all(0<=c['start']<c['end']<=data['duration']+.001 for c in cues))
    check('Cue times ordered and non-overlapping',all(cues[i]['end']<=cues[i+1]['start']+.001 for i in range(len(cues)-1)))
    check('One line respected',all('\n' not in c['text'] for c in cues))
    check('42-character limit respected',all(len(c['text'])<=42 for c in cues))
    check('Four-second maximum respected',all(c['end']-c['start']<=4.01 for c in cues))
    check('Timed words present',all(c['words'] and all(0<=w['start']<w['end']<=data['duration']+.001 for w in c['words']) for c in cues))
    text=unicodedata.normalize('NFC',' '.join(c['text'] for c in cues))
    check('French accents and context vocabulary retained',all(w in text for w in ['français','Grenoble','Élodie','FilmCraft']))
    check('Actual progress reaches completion',events[-1]['stage']=='complete' and events[-1]['progress']==1)
    check('Progress is monotonic',all(events[i]['progress']<=events[i+1]['progress'] for i in range(len(events)-1)))
    check('Source unchanged',original==digest(fixture))
    for label,media,fragment in [('silence',silent,'silencieuse'),('no audio',noaudio,'aucune piste audio')]:
        target=pathlib.Path(d)/(label+'.json')
        bad=subprocess.run([str(engine),'--input',str(media),'--output',str(target)],capture_output=True,text=True,timeout=30)
        check(label+' rejected clearly',bad.returncode!=0 and fragment in bad.stderr and not target.exists())
    target=pathlib.Path(d)/'cancelled.json'
    child=subprocess.Popen([str(engine),'--input',str(fixture),'--output',str(target)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    pids=[]
    for _ in range(200):
        r=subprocess.run(['pgrep','-P',str(child.pid)],capture_output=True,text=True)
        pids=[int(n) for n in r.stdout.split()]
        if pids:break
        time.sleep(.05)
    child.send_signal(signal.SIGTERM);child.communicate(timeout=15)
    alive=[]
    for pid in pids:
        try:os.kill(pid,0);alive.append(pid)
        except ProcessLookupError:pass
    check('Cancellation terminates Whisper child',bool(pids) and child.returncode==130 and not alive and not target.exists())
    result={'checks':checks,'passed':len(checks),'fixture':'Synthetic French Thomas voice, encoded MP4/AAC','media_duration_seconds':data['duration'],'elapsed_seconds':round(elapsed,2),'text':text,'limitations':'Synthetic speech validates packaging, French characters and timeline; not a benchmark of noisy real recordings. Quantization and ASR can still miss names or words.'}
    report.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps(result,ensure_ascii=False))
