# Dérive

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/stephanepoulin)

Menu bar app for macOS. Press play and it picks a random album from the Bandcamp artists you
choose, and plays its tracks in order. Add as many artists or labels as you like.

## Features

- Random album, played track by track
- Radio mode: a new random album and track after each track
- Thumbs down: skip a track and never hear it again
- Your own list of Bandcamp artists and labels, each one turned on or off
- Link your Bandcamp profile to play the artists and labels you follow, kept in sync
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

Click **Artists…**: the artist list opens next to the player. A narrow window grows to the right
to make room; a wide window (840 points or more) keeps its size, and the player gets narrower. Click **Hide artists** to close it. The list starts empty: the first time you press play,
the list opens. Paste the address of an artist or label on Bandcamp,
for example `artist.bandcamp.com` or any page of their site, then click **Add**. Turn an
artist off to skip them without removing them.

Click the play button next to an artist to hear a random album by that artist right away. This
turns radio mode off, so the album plays to the end, followed by other albums by that artist.

### Artists you follow on Bandcamp

In the field under the artist list, paste your Bandcamp profile, for example
`bandcamp.com/yourname`, and click **Add**: the app sees it is a profile and links it. The artists and labels it follows appear under **Following on Bandcamp**. The
profile must be public; no sign-in is needed.

The list updates at each launch, or when you choose **Refresh** in the **…** menu of that section: artists you follow on Bandcamp
are added, and artists you unfollow are removed. Turning one off here stays as you set it.
**Unlink**, in the same menu, removes these artists; artists added by hand stay. The menu also turns
all of them on or off at once.

Some artists use their own domain instead of `name.bandcamp.com`. Bandcamp sends apps that
aren't web browsers around in a loop on some of these sites, so the app can't read them and
skips them.

### How an album is picked

To pick an album, the app first picks one of the artists that are turned on, each with the same
chance, then picks one of that artist's albums at random.

## Radio mode

By default, the app plays the random album from its first track to its last. When the album ends,
another random album by the same artist starts. To change artist, click shuffle. Click the radio
button, left of shuffle, to turn on radio mode: after each track, the app picks a new artist and
album at random, then plays a random track from it. The next track is picked while the current
one plays, so there is no wait between tracks. Click the button again to go back to albums.

## Thumbs down

Click the thumbs down to skip the current track and never play it again, in radio mode and in
albums. The app remembers these tracks by their Bandcamp ID. To hear one again, click
**Artists…**, open the **Thumbs down** tab and click the undo arrow next to it. Not sure it's the right track?
Click its play button to listen to it first.

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
| `derive://artists` | Show or hide the artist list |
| `derive://radio` | Turn radio mode on |
| `derive://album` | Turn radio mode off: play whole albums |
| `derive://dislike` | Thumbs down on the current track |
| `derive://artist?url=name.bandcamp.com` | Play a random album by that artist (radio off) |

From a terminal: `open -g derive://toggle` (`-g` keeps the app in the background).

The app was called Sonnov before: `sonnov://` links still work, and its settings are kept.

In Stream Deck, add a **Website** action (System category) with the URL, or an action that runs the
command above.

## Support

If Dérive saves you from picking the next album yourself, you can buy me a coffee.

<a href="https://buymeacoffee.com/stephanepoulin"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" height="40"></a>

Made by [Stéphane Poulin](https://www.stephanepoulin.com).
