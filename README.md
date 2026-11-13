<img src="Resources/AppIcon.png" width="128" alt="Dérive app icon">

# Dérive

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/stephanepoulin)

Menu bar app for macOS. Press play and it picks a random album from the Bandcamp artists you
choose, and plays its tracks in order. Add as many artists or labels as you like.

## Features

- Random album, played track by track
- Radio mode: a new random album and track after each track
- Thumbs up: keep the tracks you like in a list, and play only them with Favorites
- Thumbs down: skip a track and never hear it again
- History of the tracks played, and an option to avoid repeats
- Media keys and Control Center's Now Playing
- Your own list of Bandcamp artists and labels, each one turned on or off
- Link your Bandcamp profile to play the artists and labels you follow, kept in sync
- Sign in to Bandcamp: your profile links by itself, artists' messages show in Community, and
  you can follow or unfollow artists from the app
- Every artist that is turned on has the same chance, whatever the size of their catalog
- Album cover and current track, with a bar to see the time left and move in the track
- A player window that stays open, with a large cover, to keep on your desktop
- Play/pause, next track, and the dice for another random album
- Open the current album on Bandcamp
- The artist playing: photo, bio, upcoming shows and what fans wrote about the album
- The merch of the artist playing
- The artist's community page: new releases to play, listening parties, recent supporters
- Shuffle in a fan's collection, from a supporter or a fan comment, and back to yours in a click

## Build

Requires macOS 13+ and Swift 5.9+.

```sh
./build.sh
open Derive.app
```

To install it in Applications, or to update the installed copy:

```sh
./build.sh install
```

This builds the app, quits the copy that is running, moves the new one to
`/Applications/Derive.app` and opens it. Only one copy is kept, so `derive://` links always reach
the installed app. Your artists and settings stay as they were.

To open Dérive when you log in, click **…** at the bottom right of the menu bar window and
choose **Open at Login**. It appears in System Settings › General › Login Items, where you can
also turn it off. **Quit Dérive** is in the same menu.

The app icon is drawn by `tools/make-icon.swift`. To change it, edit the script, then run
`swift tools/make-icon.swift icon.png`, turn `icon.png` into `Resources/AppIcon.icns` with
`iconutil`, and save a 256-pixel copy as `Resources/AppIcon.png` for this README.

## Artists

Click the sidebar icon at the top right of the player window: the side panel opens next to the
player, with the artist list in its People tab (see [Panel tabs](#panel-tabs)). A narrow window
grows to the right to make room; a wide window (840 points or more) keeps its size, and the
player gets narrower. Click the icon again to close it. In the menu bar
player, **Panel** opens the window with its panel. The list starts empty: the first time you press
play, the panel opens.

To add an artist or a label, click **+** at the top right of the list, paste the address of
their Bandcamp site, for example `artist.bandcamp.com` or any page of their site, then click
**Add**. Turn an artist off with its switch to skip them without removing them.

Click the play button next to an artist to hear a random album by that artist right away. This
turns radio mode off, so the album plays to the end, followed by other albums by that artist.

### Artists you follow on Bandcamp

The simplest way: click **Sign In to Bandcamp…**, in the empty list or in the **+** panel, and
sign in. Dérive links your profile by itself (see [Signing in to Bandcamp](#signing-in-to-bandcamp)).

Without signing in: click **+** and paste your Bandcamp profile, for example
`bandcamp.com/yourname`: the app sees it is a profile and links it. The profile must be public.

Either way, the artists and labels it follows appear under **Following on Bandcamp**.

The list updates at each launch, or when you choose **Refresh** in the **…** menu at the top
right: artists you follow on Bandcamp are added, and artists you unfollow are removed. Turning
one off here stays as you set it. **Unlink**, in the same menu, removes these artists; artists
added by hand stay. The menu also turns all of them on or off at once.

### Artists that can't be played

Some artists show in grey, with the reason in orange:

- **No audio on Bandcamp**: their releases have no tracks to listen to, even in a web browser.
- **Site can't be read by the app**: they use their own domain instead of `name.bandcamp.com`,
  and Bandcamp sends apps that aren't web browsers around in a loop there. They play in a web
  browser.
- **No releases on Bandcamp**: their page lists nothing.

The app finds these when it tries to play them: at random, it then picks another artist, and
skips them for a week before trying them again, in case the artist changed something. The play
button next to an artist finds out right away. Artists are looked at only when they come up, so
the app never sends Bandcamp a burst of requests.

When Bandcamp is busy or refuses requests, its error pages are not taken for an artist without
releases: nothing is marked. A request that gets no answer gives up after 15 seconds, and the
player says "Bandcamp isn't answering right now" instead of loading on and on.

### How an album is picked

To pick an album, the app first picks one of the artists that are turned on, each with the same
chance, then picks one of that artist's albums at random.

## Radio mode

By default, the app plays the random album from its first track to its last. When the album ends,
another random album by the same artist starts. To change artist, click the dice, left of play: another album at random. Check **Radio**
at the bottom of the player window (or in the "…" menu of the menu bar player) to turn on radio
mode: after each track, the app picks a new artist and album at random, then plays a random track
from it. The next track is picked while the current one plays, so there is no wait between
tracks. Uncheck it to go back to albums.

## Thumbs up

Click the thumbs up, right of next, to keep the track playing in the **Liked** tab; it turns
blue. Click it again to remove it. The Liked tab lists these tracks with their cover: click a
cover or play to hear one again, or the undo arrow to remove it. A thumbs up removes a thumbs down, and the other way around.

### Favorites

Check **Favorites** at the bottom of the player window (or in the "…" menu of the menu bar
player) to play only your thumbs up: each track is picked at random among them, and radio doesn't
apply. With **Avoid repeats** on, the tracks heard lately come last. Playing an artist from the
list, or a new release from Community, turns Favorites off.

## Thumbs down

Click the thumbs down to skip the current track and never play it again, in radio mode and in
albums. The app remembers these tracks by their Bandcamp ID. To hear one again, open the side panel,
open the **Thumbs down** tab and click the undo arrow next to it. Not sure it's the right track?
Click its play button to listen to it first.

## Panel tabs

The panel next to the player has two groups of tabs, each tab shown by an icon and a number.
Point at a tab to see its name.

On the left, the album playing. These tabs change with every album:

| Icon | Tab | Number |
| --- | --- | --- |
| (i) | The artist playing | Upcoming shows, when there are any |
| Speech bubbles | Community page of the artist playing | Posts listed, when there are any |
| Cart | Merch of the artist playing | Items still available |

Their numbers show without opening them, as soon as the album starts.

At each new track, while one of these tabs is open, the panel goes through them by itself,
fading from one to the next: the (i) tab first, then Community after 30 seconds, then Merch 30
seconds later. On a short track, the next track starts the cycle again. A tab with nothing to
show is skipped: no community page or posts, or no merch still available. Click a tab to stop
this until the next track. While one of your library tabs is open, the panel stays on it.

On the right, your library. These tabs don't change with the music:

| Icon | Tab | Number |
| --- | --- | --- |
| People | Artists to pick from | Artists in the list |
| Thumbs up | Tracks given a thumbs up | Tracks |
| Thumbs down | Tracks given a thumbs down | Tracks |
| Clock | History of the tracks played | Tracks played today |

## Artist playing

The **(i)** tab shows who plays the album playing, read from its Bandcamp page:

- the artist's photo, name and city, bio and links;
- upcoming shows, with the venue and the city; click one to open its page;
- the album: release date, tags, text and credits, and the comments fans left on it, with their
  favorite track.

For a label, the photo, bio and shows are the label's.

### Follow and unfollow

Signed in to Bandcamp, the **Follow** button on the artist's photo (and at the top of the
Community tab) follows the artist or label on Bandcamp, as the button of their page does. They
join your followed artists in Dérive right away. **Following** shows the ones you follow: point at
it and click to unfollow, which removes them from your followed artists. Signed out, the button
opens the sign-in window.

## Community

The **Community** tab shows the artist's Bandcamp community page (/community), for artists who
have one:

- the fans who bought something lately; click one to open their Bandcamp profile;
- the latest posts, always in full: new releases, listening parties and messages from the
  artist, with their date, likes and comments.

Click a supporter to shuffle in their collection (see [Someone else's collection](#someone-elses-collection));
right-click one to open their Bandcamp page.

Click the cover of a new release (a play glyph shows on hover) to play it in Dérive, from its first track; radio mode turns off
so the whole release plays.

Bandcamp shows the text of the artist's messages only to followers signed in on Bandcamp.
Signed out, these messages are gathered in one line at the top of the posts: how many there are
and when the latest came, marked **New** when it is less than two weeks old. Click the arrow to
read them on Bandcamp.

### Signing in to Bandcamp

Signing in does two things: Dérive links your profile by itself, so it plays the artists you
follow, and it shows their messages in the Community tab. Click **Sign In to Bandcamp…** in the
empty artist list, in the + panel or in a "…" menu, or **Sign in to Bandcamp to read them** in
the Community tab. Bandcamp's own sign-in page opens in a window of the app; it closes by itself
once you're signed in.

- You type your password in Bandcamp's page: Dérive never sees it.
- When Bandcamp emails you to confirm a new device, don't click the link in the email: it would
  confirm your browser, not Dérive. Copy the link, paste it in the field at the bottom of the
  sign-in window and click **Open**.
- The session stays in the app's web data, and is sent only when reading community pages on
  bandcamp.com.
- When a profile is linked already, signing in doesn't change it.
- **Sign Out of Bandcamp** in a "…" menu removes the session from the app. The linked profile
  stays: unlink it in the "…" menu of the artist list.
- Signed in, the messages of artists you don't follow stay locked: follow them on Bandcamp to
  read them.

## History

The **History** tab lists the last 300 tracks played, the last one first, with their cover and
when they played. Click a cover or the play button to hear a track again, the arrow to open its album on Bandcamp, or
the thumbs down to never play it again. **Clear…** empties the list.

### Avoid repeats

Every artist has the same chance at each pick, so the few tracks of an artist with a small
catalog can come back often. Turn on **Avoid repeats**, at the top of the History tab, to skip:

- in radio mode, the tracks heard in the last 24 hours;
- in album mode, the albums heard in the last 24 hours;
- the artist just heard.

When nothing else can play, a track plays again rather than nothing. Off by default.

## Someone else's collection

Click a fan, among the recent supporters of the Community tab or the fan comments of the (i) tab,
to shuffle in their public Bandcamp collection instead of your artists. A blue banner at the top
of the player shows their picture and name, and how much of the collection is loaded; the rest
loads in the background, unhurried. Click the name to open their Bandcamp page.

Radio works there as with your artists: on, a random track of their collection after each track;
off, whole albums of their collection, one after the other. **Favorites** leaves their collection
to play your thumbs up.

Click **Back to mine** in the banner to return to your artists, with a new random pick right
away. Playing an artist from your list, a new release from Community, or turning on Favorites
also brings you back. The collection isn't kept: at launch, Dérive is back with your artists.

## Merch

The **Merch** tab of the side panel shows what the artist playing sells on Bandcamp: CDs,
records, tapes, clothes, prints. A slideshow at the top goes through every item still available,
one at a time, every 6 seconds; every item, sold out or not, is listed below it. Items of the album playing come first, with an
orange note; sold-out items are dimmed. Click an item to open it on Bandcamp.

For a label, this is the label's merch. Artists whose site can't be read by the app show no
merch either.

## Player window

The menu bar window closes when you click elsewhere. To keep the player on screen, click the pin
on the cover: the player opens in its own window. Resize it to make the cover bigger. Check
**On top** to keep it above other apps.

The window takes the main color of the cover, and the next cover fades in over the previous one.

Under the cover, a bar shows where the track is, with the time played on the left and the time
left on the right. Click or drag the bar to move in the track. Control Center's bar moves in the
track too.

The window keeps its place and size, and comes back at launch if it was open when you quit.

A short message at the bottom of the player says what an action just did: favorites or radio on
or off, on top or not, thumbs up or down. It fades out after a few seconds.

## Media keys and Control Center

The media keys of the keyboard control Dérive while it is the app playing:

| Key | Pressed | Held down |
| --- | --- | --- |
| Play/pause | Play or pause | — |
| Next | Next track | Moves fast forward in the track |
| Previous | Back to the start of the track (there is no previous track) | Moves fast back in the track |

Control Center's Now Playing shows the track, the artist and the cover.

On a Stream Deck, a media key held a little long counts as held down. For a next track every time,
use a `derive://next` link instead (see below).

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
| `derive://panel` | Show or hide the side panel (`derive://artists` works too) |
| `derive://radio` | Turn radio mode on |
| `derive://album` | Turn radio mode off: play whole albums |
| `derive://dislike` | Thumbs down on the current track |
| `derive://like` | Thumbs up on the current track, or remove it |
| `derive://favorites` | Turn Favorites on or off |
| `derive://collection?user=name` | Shuffle in a fan's collection; `derive://collection` alone goes back to yours |
| `derive://signin` | Open the Bandcamp sign-in window |
| `derive://artist?url=name.bandcamp.com` | Play a random album by that artist (radio off) |

From a terminal: `open -g derive://toggle` (`-g` keeps the app in the background).

The app was called Sonnov before: `sonnov://` links still work, and its settings are kept.

In Stream Deck, add a **Website** action (System category) with the URL, or an action that runs the
command above.

## Support

If Dérive saves you from picking the next album yourself, you can buy me a coffee.

<a href="https://buymeacoffee.com/stephanepoulin"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" height="40"></a>

Made by [Stéphane Poulin](https://www.stephanepoulin.com).
