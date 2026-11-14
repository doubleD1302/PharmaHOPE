from pathlib import Path
import json, hashlib, html
from PIL import Image
root=Path(__file__).resolve().parent
items=[]
for p in sorted(root.glob('*.png')):
 with Image.open(p) as im:
  items.append({'file':p.name,'size':list(im.size),'mode':im.mode,'alpha':list(im.getchannel('A').getextrema()) if 'A' in im.getbands() else None,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'status':'candidate'})
(root/'manifest.json').write_text(json.dumps({'status':'candidate','count':len(items),'unique_sha256':len({i['sha256'] for i in items}),'note':'Generated candidates. Alpha edge quality, consistency, animation and iOS behavior are not yet approved.','assets':items},ensure_ascii=False,indent=2),encoding='utf8')
cards=''.join('<article><div><img loading="lazy" src="'+html.escape(x['file'],quote=True)+'"></div><p>'+html.escape(x['file'])+'</p></article>' for x in items)
(root/'preview.html').write_text('''<!doctype html><html lang="vi"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hope • Vườn tự nhiên</title><style>body{font:15px system-ui;background:#f4f5ed;color:#344936;padding:24px}section{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:16px}article{background:white;border-radius:16px;padding:12px}article div{height:180px;background:linear-gradient(45deg,#e3e7dd 25%,transparent 25%,transparent 75%,#e3e7dd 75%),linear-gradient(45deg,#e3e7dd 25%,#f8f8f4 25%,#f8f8f4 75%,#e3e7dd 75%);background-size:20px 20px;background-position:0 0,10px 10px;display:grid;place-items:center}img{width:100%;height:100%;object-fit:contain}p{overflow-wrap:anywhere}</style><h1>Hope • Vườn tự nhiên</h1><p>'''+str(len(items))+''' ảnh ứng viên, chưa duyệt viền trong suốt và chuyển động.</p><section>'''+cards+'''</section></html>''',encoding='utf8')
print('count',len(items),'unique',len({i['sha256'] for i in items}))
