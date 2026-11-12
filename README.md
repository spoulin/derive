# PlaySonnov

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/stephanepoulin)

Menu bar app for macOS. Press play and it picks a random album from the Bandcamp artists you
choose, and plays its tracks in order. It starts with
[Sonnov](https://sonnovdrone.bandcamp.com/music); add as many artists or labels as you like.

## Features

- Random album, played track by track
- Your own list of Bandcamp artists and labels, each one turned on or off
- Every artist that is turned on has the same chance, whatever the size of their catalog
- Album cover and current track
- Play/pause, next track, and shuffle (new random album)
- Open the current album on Bandcamp

## Build

Requires macOS 13+ and Swift 5.9+.

```sh
./build.sh
open Sonnov.app
```

## Artists

Click **Artists…** in the menu bar window. Paste the address of an artist or label on Bandcamp,
for example `sonnovdrone.bandcamp.com` or any page of their site, then click **Add**. Turn an
artist off to skip them without removing them.

To pick an album, the app first picks one of the artists that are turned on, each with the same
chance, then picks one of that artist's albums at random.

## Remote control (Stream Deck, scripts)

The app handles `sonnov://` URLs while it is running:

| URL | Action |
| --- | --- |
| `sonnov://toggle` | Play / pause |
| `sonnov://play` | Play |
| `sonnov://pause` | Pause |
| `sonnov://next` | Next track |
| `sonnov://shuffle` | New random album |

From a terminal: `open -g sonnov://toggle` (`-g` keeps the app in the background).

In Stream Deck, add a **Website** action (System category) with the URL, or an action that runs the
command above.

## Support

If PlaySonnov saves you from picking the next drone album yourself, you can buy me a coffee.

<a href="https://buymeacoffee.com/stephanepoulin"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" height="40"></a>

Made by [Stéphane Poulin](https://www.stephanepoulin.com).
