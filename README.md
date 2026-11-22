<img src="Clearout/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="64" height="64" alt="">

# Clearout

A private disk cleaner for your Mac. See what fills it, then clean it up.

## Get it

[Download Clearout](https://github.com/barry-napier/clearout/releases/latest/download/Clearout.dmg),
open it, and drag Clearout to Applications. It needs macOS 15 or newer.
Clearout never uses the network, so it cannot update itself. Download new versions the same way.

Website: [clearout.bnapier.dev](https://clearout.bnapier.dev)

## Use

1. Open **Clearout** from Applications. It also lives in your menu bar.
2. Turn on **Full Disk Access** when it asks.
3. Click **Scan my stuff**, then **Clean up**. Start with **Easy wins**.
4. Click **Check and move to Trash**.
5. Empty the Trash in Finder. Space comes back only then.

Closing the window leaves Clearout in the menu bar. Choose **Quit Clearout** there to stop it.

## Safety

- Scanning reads names and sizes. It does not open your files.
- Scanning cannot make iCloud download files (`Clearout/Safety/CloudGuard.swift`).
  Never remove that. Without it, one test scan downloaded 3.3 GB.
- Clearout only moves things to the Trash. It never erases them.
- It will not move anything an open app is using.
- Cache folders that hold a browser profile (cookies, passwords) are locked.
- It will not trash code that is saved nowhere else: no online copy, changes not saved,
  saves not uploaded, parked changes, or a private `.env` file.
- System files, app data, media libraries and main folders are locked.
- Desktop and Documents are locked when they sync with iCloud. Use **Remove Download** in Finder.
- It has no server and does not use the network.

## Smart picks

Plain rules pick big things you have not changed for a month or more, and zips that sit
next to a folder with the same name. Then Apple Intelligence says what each one looks like
(macOS 26 and up). It runs on your Mac and sees names only.

The AI must never decide what is junk. When tested, it found 0 of 8 junk items, and it once
called family videos junk. See `Clearout/Intelligence/Explainer.swift`.

## Limits

- Sizes are close, not exact. macOS can share space between copies.
- Cloud drive folders in `~/Library/CloudStorage` are skipped.
- It needs macOS 15 or newer.

## Build from source

You need Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and an Apple Development certificate.

```sh
./scripts/build.sh   # build, sign, install, relaunch
./scripts/test.sh    # run the tests
```

The Xcode project is generated from `project.yml`. Edit that, not the project.

- `Clearout/App`: menu bar, windows, and what the screens can ask for
- `Clearout/Scan`: reads sizes, chooses Smart picks
- `Clearout/Intelligence`: asks Apple's AI what a thing looks like
- `Clearout/Safety`: what may go to the Trash, and the iCloud block
- `Clearout/UI`: native windows
- `Clearout/Web`: the screens, in plain HTML, CSS and JS
- `scripts/make-icon.swift`: draws the icon
- `site/`: the website, in plain HTML, CSS and JS

## Releasing

Commit, push `main`, then run this on a Mac with a Developer ID certificate:

```sh
./scripts/release.sh 0.2.0 --publish
```

It runs the tests, builds, signs, has Apple check it, and publishes the DMG on GitHub.
The website's Download button always gets the newest release.
The Apple login is the `clearout-notary` keychain profile. The script says how to save one.

After you change `site/`, publish it with `cd site && vercel --prod`.
