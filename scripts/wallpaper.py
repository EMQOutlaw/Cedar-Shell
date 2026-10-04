#!/usr/bin/env python3
"""Render the native SVG field-station design to Omarchy's required PNG preview."""
from pathlib import Path
import re
import subprocess
root = Path(__file__).resolve().parents[1]
p = dict(re.findall(r'property color (\w+): "(#[0-9A-Fa-f]{6})"', (root/'Theme.qml').read_text()))
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="2560" height="1440" viewBox="0 0 2560 1440">
<defs>
<pattern id="grid" width="64" height="64" patternUnits="userSpaceOnUse"><path d="M64 0H0V64" fill="none" stroke="{p['teal']}" stroke-opacity=".09" stroke-width="1"/></pattern>
<radialGradient id="light"><stop stop-color="{p['green']}" stop-opacity=".12"/><stop offset="1" stop-color="{p['background']}" stop-opacity="0"/></radialGradient>
</defs>
<path fill="{p['background']}" d="M0 0H2560V1440H0Z"/>
<path fill="url(#grid)" d="M0 0H2560V1440H0Z"/>
<ellipse cx="1680" cy="820" rx="1050" ry="760" fill="url(#light)"/>
<g fill="none" stroke="{p['teal']}" stroke-opacity=".25" stroke-width="1">
<path d="M100 230V140L140 100H440 M2120 100H2460V350 M100 1090V1340H440 M2120 1340H2420L2460 1300V1110"/>
<circle cx="1700" cy="790" r="310"/><circle cx="1700" cy="790" r="325" stroke-dasharray="2 24"/>
<path d="M1655 790H1745 M1700 745V835"/>
</g>
<path d="M1418 936A318 318 0 0 1 1530 521" fill="none" stroke="{p['green']}" stroke-opacity=".6" stroke-width="2"/>
<circle cx="1938" cy="1000" r="4" fill="{p['amber']}"/>
<g font-family="DejaVu Sans Mono" fill="{p['green']}">
<text x="180" y="1190" font-size="62" letter-spacing="18">CEDAR</text>
<text x="183" y="1235" font-size="16" letter-spacing="3" fill="{p['muted']}">A COLD, LIVING LIGHT IN THE DARK WOODS</text>
<text x="180" y="175" font-size="14" letter-spacing="3" fill="{p['teal']}">APPALACHIAN MEMORY / FIELD STATION 01</text>
</g></svg>'''
(root/'backgrounds/field-station.svg').write_text(svg)
(root/'themes/backgrounds').mkdir(exist_ok=True)
subprocess.run(['magick', '-background', p['background'], str(root/'backgrounds/field-station.svg'), str(root/'themes/backgrounds/field-station.png')],check=True)
subprocess.run(['magick', str(root/'themes/backgrounds/field-station.png'), '-resize', '960x540', str(root/'themes/preview.png')],check=True)
