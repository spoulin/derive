# Dérive

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/stephanepoulin)

Menu bar app for macOS. Press play and it picks a random album from the Bandcamp artists you
choose, and plays its tracks in order. Add as many artists or labels as you like.

## Features

- Random album, played track by track
- Radio mode: a new random album and track after each track
- Thumbs down: skip a track and never hear it again
- Your own list of Bandcamp artists and labels, each one turned on or off
- Every artist that is turned on has the same chance, whatever the size of their catalog
- Album cover and current track
- A player window that stays open, with a large cover, to keep on your desktop
- Play/pause, next track, and shuffle (new random album)
- Open the current album on Bandcamp

## Build

Requires macOS 13+ and Swift 5.9+.

```sh
./build.sh
open Derive.app
```

## Artists

The list starts empty: the first time you press play, the Artists window opens. You can also
click **Artists…** in the menu bar window. Paste the address of an artist or label on Bandcamp,
for example `artist.bandcamp.com` or any page of their site, then click **Add**. Turn an
artist off to skip them without removing them.

To pick an album, the app first picks one of the artists that are turned on, each with the same
chance, then picks one of that artist's albums at random.

## Radio mode

By default, the app plays the random album from its first track to its last. Click the radio
button, left of shuffle, to turn on radio mode: after each track, the app picks a new artist and
album at random, then plays a random track from it. The next track is picked while the current
one plays, so there is no wait between tracks. Click the button again to go back to albums.

## Thumbs down

Click the thumbs down to skip the current track and never play it again, in radio mode and in
albums. The app remembers these tracks by their Bandcamp ID. To hear one again, open
**Artists…**, expand **Thumbs down** and click the undo arrow next to it.

## Player window

The menu bar window closes when you click elsewhere. To keep the player on screen, click the pin
on the cover: the player opens in its own window. Resize it to make the cover bigger. Check
**On top** to keep it above other apps.

The window takes the main color of the cover, and the next cover fades in over the previous one.

The window keeps its place and size, and comes back at launch if it was open when you quit.

## Remote control (Stream Deck, scripts)

The app handles `derive://` URLs while it is running:

| URL | Action |
| --- | --- |
| `derive://toggle` | Play / pause |
| `derive://play` | Play |
| `derive://pause` | Pause |
| `derive://next` | Next track |
| `derive://shuffle` | New random album |
| `derive://window` | Open the player window |
| `derive://radio` | Turn radio mode on |
| `derive://album` | Turn radio mode off: play whole albums |
| `derive://dislike` | Thumbs down on the current track |

From a terminal: `open -g derive://toggle` (`-g` keeps the app in the background).

The app was called Sonnov before: `sonnov://` links still work, and its settings are kept.

In Stream Deck, add a **Website** action (System category) with the URL, or an action that runs the
command above.

## Support

If Dérive saves you from picking the next album yourself, you can buy me a coffee.

<a href="https://buymeacoffee.com/stephanepoulin"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" height="40"></a>

Made by [Stéphane Poulin](https://www.stephanepoulin.com).
