"""Static design/package checks. This is not an Apple SDK build or a layout test."""
from pathlib import Path
import argparse
import json
import re
import yaml
from PIL import Image
from tree_sitter import Language, Parser
import tree_sitter_swift

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--report', type=Path)
args = parser.parse_args()
issues = []
project = yaml.safe_load((ROOT / 'project.yml').read_text(encoding='utf-8'))
for target, config in project['targets'].items():
    for source in config['sources']:
        if not (ROOT / source['path']).exists():
            issues.append(f'{target}: missing source {source["path"]}')

catalog = ROOT / 'PharmaTask/Shared/Resources/HopeAssets.xcassets'
sets = list(catalog.glob('*.imageset'))
for image_set in sets:
    info = json.loads((image_set / 'Contents.json').read_text())
    if not info.get('properties', {}).get('preserves-vector-representation'):
        issues.append(f'{image_set.name}: vector preservation disabled')
    for image in info['images']:
        file = image_set / image['filename']
        if not file.exists(): issues.append(f'Missing asset: {file}')
        elif b'/Subtype /Image' in file.read_bytes(): issues.append(f'{file.name}: raster embedded in PDF')

icon = ROOT / 'PharmaTask/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
with Image.open(icon) as image:
    if image.size != (1024, 1024): issues.append('AppIcon must be 1024x1024')
    if image.convert('RGBA').getchannel('A').getextrema() != (255, 255): issues.append('AppIcon must be opaque')

swift_parser = Parser(Language(tree_sitter_swift.language()))
swift_files = list(ROOT.rglob('*.swift'))
asset_names = {item.stem for item in sets}
for file in swift_files:
    source = file.read_bytes()
    tree = swift_parser.parse(source)
    nodes = [tree.root_node]
    while nodes:
        node = nodes.pop()
        if node.type == 'ERROR' or node.is_missing:
            issues.append(f'{file.relative_to(ROOT)}:{node.start_point.row + 1}: grammar {node.type}')
        nodes.extend(node.children)
    text = source.decode('utf-8')
    if '\ufffd' in text: issues.append(f'{file.name}: invalid replacement glyph')
    if re.search(r'\bPharmaTheme\.', text): issues.append(f'{file.name}: unresolved legacy theme')
    for name in re.findall(r'(?:Image|HopeIllustration)\("(Hope[^"]+)"', text):
        if name not in asset_names: issues.append(f'{file.name}: unknown image {name}')

tokens = json.loads((ROOT / 'DesignAssets/tokens.json').read_text())['colors']
def luminance(color):
    rgb = [int(color[index:index + 2], 16) / 255 for index in (1, 3, 5)]
    values = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
    return sum(value * weight for value, weight in zip(values, (0.2126, 0.7152, 0.0722)))

contrasts = {}
for mode in ('light', 'dark'):
    for ink, surface in [('ink', 'background'), ('ink', 'surface'), ('secondary', 'surface'),
                         ('secondary', 'surfaceMuted'), ('onAccent', 'accent'), ('urgent', 'urgentSurface')]:
        values = sorted([luminance(tokens[ink][mode]), luminance(tokens[surface][mode])])
        ratio = (values[1] + 0.05) / (values[0] + 0.05)
        contrasts[f'{mode}:{ink}/{surface}'] = round(ratio, 2)
        if ratio < 4.5: issues.append(f'{mode} {ink}/{surface}: contrast {ratio:.2f} < 4.5')

result = {'scope': 'Static assets, grammar and design tokens only; not an iOS build or native render',
          'swift_files': len(swift_files), 'vector_image_sets': len(sets),
          'asset_bytes': sum(file.stat().st_size for file in catalog.rglob('*') if file.is_file()) + icon.stat().st_size,
          'contrast_ratios': contrasts, 'issues': issues, 'passed': not issues}
if args.report:
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False, indent=2))
raise SystemExit(bool(issues))
