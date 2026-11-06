"""Package the supplied icon as Android density/adaptive launcher resources.

The original artwork is retained; only platform sizing and safe-area padding
are generated. Run from the Flutter project root (requires Pillow).
"""
from pathlib import Path
from PIL import Image

source = Image.open('assets/icon/icon.png').convert('RGBA')
res = Path('android/app/src/main/res')
for density, scale in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)]:
    folder = res / f'mipmap-{density}'
    folder.mkdir(parents=True, exist_ok=True)
    side = round(48 * scale)
    source.resize((side, side), Image.Resampling.LANCZOS).save(folder / 'ic_launcher.png')
    frame_size, art_size = round(108 * scale), round(72 * scale)
    frame = Image.new('RGBA', (frame_size, frame_size))
    art = source.resize((art_size, art_size), Image.Resampling.LANCZOS)
    inset = (frame_size - art_size) // 2
    frame.alpha_composite(art, (inset, inset))
    frame.save(folder / 'ic_launcher_foreground.png')

folder = res / 'mipmap-anydpi-v26'
folder.mkdir(parents=True, exist_ok=True)
(folder / 'ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''', 'utf-8')
background = source.getpixel((0, 0))[:3]
(res / 'values' / 'launcher_colors.xml').write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
    f'    <color name="launcher_background">#{background[0]:02x}{background[1]:02x}{background[2]:02x}</color>\n'
    '</resources>\n', 'utf-8')
print('Generated five launcher icon densities and Android adaptive resources.')
