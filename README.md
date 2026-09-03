# treemap

A disk usage map for macOS in one Swift file

```sh
swiftc -O treemap.swift -o treemap && ./treemap
```

<img width="600" alt="screenshot of treemap app" src="https://github.com/user-attachments/assets/79ab99b5-8942-4456-ae18-4f15a0b07fc3" />

If using regularly build and then run (optional scan directory passed via arg)

```sh
swiftc -O main.swift -o treemap 
./treemap ~/Downloads
```

Requires the Xcode command line tools (`xcode-select --install`).

## Controls

| Input | Effect |
|---|---|
| Hover | path and size in the status bar |
| Click | zoom into that folder |
| Click breadcrumb | jump to that folder (rescans if it is above the opened folder) |
| ⌘-click breadcrumb | reveal that folder in Finder |
| Esc | zoom out one level |
| Right-click | Reveal in Finder, Move to Trash, Zoom Out |
| Cmd-click | reveal in Finder |
| Cmd-O / Cmd-R / Cmd-Q | open another folder / rescan / quit |

Move to Trash has no confirmation dialog. It goes to the Trash, so it is recoverable, and the map and totals update in place without a rescan.

## What it measures

Allocated (on-disk) size, so sparse files and APFS compression show their real footprint. 
Symlinks count as small link files and are never followed. 
The scan stays on the starting volume, like `du -x`; scanning `/` shows most data under `/System/Volumes/Data`, which is where it actually lives on modern macOS. Hard-linked files are counted at every link, so totals can run higher than `du`, which dedupes by inode.

## Permissions

macOS gates ~/Desktop, ~/Documents, ~/Downloads, and much of ~/Library. 
Give your terminal Full Disk Access (System Settings > Privacy & Security), or those folders will silently scan as empty.
