"""Build flat vector PDFs and AppIcon from the editable SVG sources.

Dependencies: reportlab, svglib; @resvg/resvg-js for the icon PNG.
Set HOPE_RESVG_MODULE to a locally installed @resvg/resvg-js directory.
No external font, network request, or AI-generated artwork is required.
"""
from pathlib import Path
import json
import subprocess
from svglib.svglib import svg2rlg
from reportlab.graphics import renderPDF

HERE = Path(__file__).resolve().parent
APP = HERE.parent / 'PharmaTask'
CATALOG = APP / 'Shared/Resources/HopeAssets.xcassets'
INFO = {'author': 'xcode', 'version': 1}
CATALOG.mkdir(parents=True, exist_ok=True)
(CATALOG / 'Contents.json').write_text(json.dumps({'info': INFO}, indent=2))
for source, name in [('hope-symbol.svg', 'HopeMark'), ('hope-shift.svg', 'HopeShift'), ('hope-inbox.svg', 'HopeInbox')]:
    target = CATALOG / f'{name}.imageset'
    target.mkdir(parents=True, exist_ok=True)
    renderPDF.drawToFile(svg2rlg(str(HERE / source)), str(target / f'{name}.pdf'))
    contents = {'images': [{'filename': f'{name}.pdf', 'idiom': 'universal'}], 'info': INFO,
                'properties': {'preserves-vector-representation': True}}
    (target / 'Contents.json').write_text(json.dumps(contents, indent=2))

icons = APP / 'Resources/Assets.xcassets/AppIcon.appiconset'
icons.mkdir(parents=True, exist_ok=True)
(icons.parent / 'Contents.json').write_text(json.dumps({'info': INFO}, indent=2))
# App icons must fill their square; iOS applies its own mask.
icon_svg = (HERE / 'hope-symbol.svg').read_text().replace(' rx="32"', '')
script = "const fs=require('fs'); const {Resvg}=require(process.env.HOPE_RESVG_MODULE||'@resvg/resvg-js'); fs.writeFileSync(process.argv[1],new Resvg(fs.readFileSync(0,'utf8'),{fitTo:{mode:'width',value:1024}}).render().asPng());"
subprocess.run(['node', '-e', script, str(icons / 'AppIcon.png')], input=icon_svg.encode(), check=True)
(icons / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': INFO}, indent=2))
print('Built 3 vector PDF image sets and an opaque 1024px app icon.')
