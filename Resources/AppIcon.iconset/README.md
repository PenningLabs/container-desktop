# App Icon Setup

This directory holds the icon PNGs for the macOS .app bundle.

## Required files

Export your AppIcon SVG to PNG at each of these sizes and place them here:

| Filename              | Size      | Use                    |
|-----------------------|-----------|------------------------|
| icon_16x16.png        | 16×16     | Finder list view       |
| icon_16x16@2x.png     | 32×32     | Finder list (Retina)   |
| icon_32x32.png        | 32×32     | Finder                 |
| icon_32x32@2x.png     | 64×64     | Finder (Retina)        |
| icon_128x128.png      | 128×128   | Finder icon view       |
| icon_128x128@2x.png   | 256×256   | Finder icon (Retina)   |
| icon_256x256.png      | 256×256   | Finder large icon      |
| icon_256x256@2x.png   | 512×512   | Finder large (Retina)  |
| icon_512x512.png      | 512×512   | App Store small        |
| icon_512x512@2x.png   | 1024×1024 | App Store full size    |

## Quick generation from the 1024px PNG

If you have `sips` (built into macOS) and a single `AppIcon-1024.png`:

```bash
cd Resources/AppIcon.iconset
cp AppIcon-1024.png icon_512x512@2x.png
for size in 512 256 128 64 32 16; do
  sips -z $size $size icon_512x512@2x.png --out icon_${size}x${size}.png
done
for size in 256 128 64 32 16; do
  doubled=$((size * 2))
  sips -z $doubled $doubled icon_512x512@2x.png --out icon_${size}x${size}@2x.png
done
```

Then build the .icns:
```bash
iconutil -c icns Resources/AppIcon.iconset -o AppIcon.icns
```
