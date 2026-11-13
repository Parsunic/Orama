# Orama

The **Glance** app: a small Mac menu bar helper. Press a shortcut and it takes a screenshot, asks
an AI about it, and shows a short answer in a quiet floating box. If the
answer is about a specific spot (a button, a field, an error), it also draws a
very faint dot there. There is no Dock icon and no window: everything lives
under a small speaker icon in the menu bar.

That icon shows your Mac's current volume (no waves when silent, one to three
waves as it goes up, a crossed-out speaker when muted) and nothing else. It
never changes to show what Glance is doing, so it looks the same in a
screenshot or screen share whether answers are showing, hidden or on their way.
If you'd rather not have two speaker icons, hide the system one in System
Settings → Control Center → Sound → "Don't Show in Menu Bar".

## The two shortcuts

| Shortcut | What it does |
|---|---|
| **⌘⇧Space** | Takes a new screenshot and asks again. The old answer disappears the moment you press it. |
| **⌘⇧1** | An on/off switch for everything Glance draws. Off means nothing shows, including an answer that arrives while it's off. Switch it back on and the answer appears. |

So you can press ⌘⇧Space, switch the display off with ⌘⇧1 while the answer is
still on its way, take a clean screenshot or share your screen, then press ⌘⇧1
again to read the answer. You can change both shortcuts in the menu. They
must include ⌘ or ⌃.

## Build and run

You need macOS 14 or later and Xcode, or just the command line tools
(`xcode-select --install`).

First time, download the code into a folder called Orama in your home folder:

```bash
git clone https://github.com/Parsunic/orama.git ~/Orama
```

```bash
cd ~/Orama && ./build.sh
```

To update later, one command fetches the newest code and rebuilds:

```bash
cd ~/Orama && git pull && ./build.sh
```

That builds `build/Glance.app` and opens it. To put it in Applications (which
"Open Glance when I log in" needs), run `./build.sh --install` instead.

**First run:**
1. Click the speaker icon in the menu bar.
2. Pick a service (Google Gemini Flash-Lite is the default, built for speed), paste your API key and press **Save**.
3. Press ⌘⇧Space. macOS asks for Screen Recording permission. Allow it in System Settings, then press **Reopen Glance** in the menu. macOS usually only applies this permission after a restart.

**About signing:** macOS remembers permissions by the app's signature.
Without a certificate, every rebuild counts as a new app, so you re-allow
Screen Recording each time. Fix it once:

1. Open **Keychain Access** (⌘Space, type "Keychain Access").
2. In the menu bar: **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Name: `Glance Signing`. Identity Type: **Self-Signed Root**. Certificate Type: **Code Signing**. Click **Create**.

`build.sh` finds that certificate by name (or an "Apple Development" one, if
you have it) and signs with it, so the permission sticks across rebuilds.

## Which AI service is fastest?

It depends on your network and your account, so Glance measures it for you.
Save keys for a couple of services, then press **Compare all saved services**
in the menu. It sends each one a tiny picture and times the reply.

From published benchmarks, Groq usually answers fastest and Google's Gemini
Flash-Lite comes close while handling screenshots well. That's why Gemini
Flash-Lite is the default. Model names change often, so press **List** next to
the model field to see the real names your key can use.

Speed tips, all in the menu:
- **Picture sent → Fastest** uploads a smaller screenshot. Use Sharpest if the text on screen is tiny.
- **Give up after** sets how long to wait for the AI before showing an error.
- **Thinking** can be lowered on services that support it ("low", or "none" on some).

## How the faint dot finds its spot

AI models are good at saying what to look at, but only roughly right about
where. So Glance also reads the text on your screen with the Mac's own
built-in text recognition (on your computer, free, no extra permission). If the
AI names the text at its spot, the dot snaps exactly onto that text. The
status line in the menu says "dot snapped to text" when that happened.

The dot picks a dark or light tone from what's underneath it. Its strength and
size are adjustable, and **Preview** shows it in the middle of the screen. If
"Increase contrast" is on in Accessibility settings, the dot is never fainter
than 25%.

## Privacy

- A screenshot is taken only when you press the shortcut, and only of the display your pointer is on. Glance's own windows are left out of it.
- That screenshot is sent to the AI service you chose, so anything on screen goes with it.
- API keys are stored in the macOS Keychain, not in a settings file.

## What's not built yet

**The local backup model.** The waiting logic is already in place and tested:
the cloud is asked first, and a backup on your Mac would only start if the
cloud is slow (after 1.5 seconds) or fails. Whichever answers first is shown.
To add the backup, pass a function as `local:` where `runHedged` is called in
`Sources/Glance/AppController.swift`. Ollama speaks the same OpenAI-style
format, so a second `CloudClient` pointed at `http://localhost:11434/v1` would
do it.

## Project layout

- `Sources/GlanceCore`: all the logic that doesn't need the Mac's user interface, with tests: reading the AI's reply, the shortcut switch, coordinate conversion, text snapping, the cloud/backup race, and building requests.
- `Sources/Glance`: the app itself: menu bar panel, shortcuts, screen capture, text recognition, the floating box and the dot.
- `Tests/GlanceCoreTests`: run with `swift test` (needs full Xcode, not just the command line tools).
