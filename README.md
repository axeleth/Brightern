# Brightern

Makes the Tern Setups OLED monitor follow the MacBook's brightness.

Use the brightness keys, the Control Center slider or auto-brightness exactly as before. macOS shows its own brightness indicator and adjusts the MacBook screen, and Brightern copies that level to the monitor over DDC/CI (the standard monitor-control channel over USB-C). Brightern has no brightness UI of its own; it only adds a small sun icon to the menu bar.

## Install

```bash
scripts/install.sh
```

Builds with the Swift compiler from the Command Line Tools (no Xcode, nothing downloaded) and installs to `~/Applications/Brightern.app`. Turn on **Open at Login** from the sun icon's menu to start it automatically; you can switch that off again in System Settings → General → Login Items.

## Menu

- **Status line**: e.g. `MacBook 62% → Monitor 62%`
- **Pause Syncing**: the monitor keeps its current level and its own buttons work as usual. Resuming snaps it back to the MacBook's level.
- **Calibrate…**: the two screens use different technology (LCD and OLED), so the same percentage may not look equally bright. Set the MacBook with the brightness keys, drag the slider until the monitor looks the same, and click **Save This Level**. Do this at a few levels (e.g. dim, medium, bright). Brightern interpolates between the saved levels. **Reset to 1:1** undoes it.

## How it works

| Piece | What it does |
| --- | --- |
| `BuiltInDisplay.swift` | Reads the MacBook's brightness (read only; Brightern never changes it). |
| `SyncEngine.swift` | Gets a notification from macOS on every brightness change and works out the monitor level. Re-syncs after sleep, opening the lid, or re-plugging the monitor. |
| `MonitorLink.swift` | Sends DDC commands on a background queue. Merges rapid changes (macOS animates brightness), spaces commands 50 ms apart, and reads the level back after each burst, because the monitor silently drops commands while it's busy. |
| `TernMonitor.swift` | Finds this monitor (EDID vendor 19083 "RTK", product 159) and speaks DDC/CI to it. Other monitors are never touched. |
| `BrightnessCurve.swift` | Maps MacBook level → monitor level; 1:1 until calibrated. |

It uses two private macOS functions (DisplayServices and IOAVService, the same ones Lunar and MonitorControl use), loaded at runtime. If a macOS update removes them, the menu shows "Not available on this version of macOS" and nothing else is affected. No admin rights, no system files, no special permissions.

## Check it's working

```bash
scripts/check.sh          # brightness-mapping tests
scripts/check.sh --live   # sets the MacBook to 30% and 70%, confirms the monitor follows, then restores
```

## Uninstall

```bash
scripts/uninstall.sh
```

Removes the app, its login item and its settings. The monitor keeps its last brightness.

## Version notes

### 1.0 (current)

The first working version, built for one setup: a MacBook Pro (M3 Pro, macOS 26) with a Tern Setups OLED monitor over USB‑C.

- The monitor follows the MacBook's brightness from the brightness keys, the Control Center slider and auto-brightness. Apple's own brightness indicator is unchanged.
- Menu bar icon with a status line, Pause Syncing, Calibrate… and Open at Login.
- Calibration by eye at any number of levels, with interpolation between them.
- Re-syncs after sleep, opening the lid, or re-plugging the monitor.
- Rapid changes are merged, commands are spaced 50 ms apart, and the final level is read back and resent if the monitor dropped it.

Known limitations:

- **Lid closed:** there's no MacBook brightness to follow, so the monitor stays where it was. Planned for a future version.
- **One monitor only:** Brightern only talks to the monitor with EDID vendor 19083 / product 159. Supporting another monitor means changing the IDs in `TernMonitor.swift`.
- **Apple Silicon only:** the DDC path uses the Apple Silicon display service (IOAVService); Intel Macs aren't supported.
