import json,sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from bcu_qemu import Channel,read_file
config=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
batch=sys.argv[2];out=Path(sys.argv[3]);end=time.monotonic()+900
while time.monotonic()<end:
    a=None;q=None
    try:
        q=Channel(config['qmp_port'],qmp=True,timeout=3)
        assert q.call('query-uuid')['UUID'].lower()==config['uuid'].lower()
        a=Channel(config['agent_port'],timeout=5)
        raw=read_file(a,fr'C:\BackgroundLab\performance\results\{batch}\qemu\summary.json')
        report=json.loads(raw.decode('utf-8-sig'))
        assert report['batchId']==batch and report['uuid'].lower()==config['uuid'].lower()
        out.write_bytes(raw)
        print(report['state']);sys.exit(0)
    except (OSError,RuntimeError,ValueError):time.sleep(3)
    finally:
        if a:a.close()
        if q:q.close()
raise TimeoutError('QEMU result timeout')
