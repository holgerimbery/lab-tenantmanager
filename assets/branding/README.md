# MATE365 brand assets

The MATE365 mark is a rounded lowercase **m** with a glossy red gradient that
matches the `#b11f4b` accent and `#9a1a41` shade used by Instruo365 and Costs365.
The PNG files have transparent backgrounds and work on light and dark surfaces.

| Asset | Use |
| --- | --- |
| `mate365-master.png` | High-resolution source; preserve transparency and aspect ratio |
| `mate365-512.png` | Website hero, app sign-in, and large brand displays |
| `mate365-192.png` | App icons and medium brand displays |
| `mate365-180.png` | Apple touch icon |
| `mate365-48.png` | App navigation and compact brand displays |
| `mate365-32.png`, `mate365-16.png` | Browser tab icons |
| `favicon.ico` | Multi-resolution browser fallback (16, 32, 48 px) |

Use the mark alongside the text **MATE365** and, where appropriate,
**Tenant Manager**. Keep text as accessible HTML rather than baking it into
the image. Use empty alternative text when the adjacent text already names
the product; use `alt="MATE365"` when the mark stands alone.

Do not stretch the mark, recolor it, or remove its transparent clear space.
These are ordinary transparent icons, not maskable icons.

To regenerate all sizes after updating the master:

```powershell
python -m pip install Pillow
python assets\branding\generate-icons.py
```

The public website is maintained on this repository's `gh-pages` branch.
The application source is maintained separately in `holgerimbery/lab-tenant-manager`.
Both should use copies of these same generated assets.
