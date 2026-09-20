# xpass

A stealth macOS HUD that listens to a call, reads your screen, and streams
answers onto a floating panel that screen-sharing cannot see.

Built with Flutter + native AppKit / ScreenCaptureKit. macOS 13 or newer.

---

## 1. Build and run

```bash
flutter pub get
./run.sh                      # build + launch correctly
./run.sh --attach             # same, plus hot reload
./run.sh --release
```

### Do not use `flutter run` for anything that touches audio or the screen

This is not a style preference — it breaks the app.

macOS applies privacy permissions to the **responsible process**, which is
whichever process launched yours. `flutter run` execs the binary as a child of
your terminal, so macOS evaluates the *terminal's* permissions instead of
xpass's:

- Screen Recording reads as denied no matter how many times you grant it to
  xpass, because TCC is checking your terminal;
- requesting Speech Recognition reads the *terminal's* `Info.plist`, finds no
  `NSSpeechRecognitionUsageDescription`, and **terminates xpass** — the app
  appears to open and immediately close.

`open`ing the bundle makes launchd responsible, and xpass is judged on its own
permissions. That is all `run.sh` does. For hot reload, `run.sh --attach`
launches the bundle properly and then runs `flutter attach`.

xpass detects this itself: launched from a terminal, it says so in the panel
rather than failing in four confusing ways, and refuses to make the request
that would kill it.

No CocoaPods — every dependency is a Swift Package.

If macOS refuses to attach a debugger, enable Developer Mode once:

```bash
sudo DevToolsSecurity -enable
```

### Signing

A default Flutter build is ad-hoc signed. That is **not** what breaks Screen
Recording — measured directly, macOS honoured the grant for a completely
different binary placed inside the same bundle, so the permission is keyed to
the bundle here, not the binary hash.

`./sign-setup.sh` creates a self-signed code-signing certificate and `run.sh`
signs with it when present. Worth doing if you move the bundle around or
distribute it, and harmless otherwise — but it is not the fix for a permission
that reads as denied. That is almost always the launch method above.

To clear a stale grant and start over:

```bash
tccutil reset ScreenCapture com.xpass.app
tccutil reset SpeechRecognition com.xpass.app
```

## 2. First run

### Keys

Transcription needs **no key** — it runs on this Mac. Keys are only for answers:

```bash
export NVIDIA_API_KEY=nvapi-...     # spoken answers, profile answers
export GEMINI_API_KEY=AIza...       # screen solving only
```

Either paste them under **Settings › Models**, or export them and skip the UI.

A `.env` file works too — in the project root, next to the `.app`, or at
`~/.xpass/.env`. Real environment variables win over the file, and anything
typed into Settings wins over both.

### Permissions

| Permission | Needed for | Where |
|---|---|---|
| Screen Recording | screen solves **and** hearing the interviewer | Privacy & Security › Screen Recording |
| Speech Recognition | on-device transcription | prompted on first launch |
| Microphone | hearing yourself | prompted on first launch |

macOS only applies a Screen Recording grant on a **fresh launch** — quit and
reopen xpass after enabling it. The Capture tab has buttons for both.

If Screen Recording keeps reading as denied after you granted it, check the two
causes above: launched from a terminal, or re-signed by a rebuild.

### Check the meters

The footer shows `MIC` (you) and `SYS` (them). If `SYS` never moves during a
call, xpass cannot hear the other side: Screen Recording is missing, or
**System audio** is off under Capture.

---

## 3. Driving it

### Global shortcuts

Work anywhere in macOS, even while xpass is hidden and another app has focus.
They use Carbon hotkeys, so xpass never appears in the Accessibility list.

| Shortcut | Action |
|---|---|
| `⌘⌥C` | Screenshot what you are looking at and solve it |
| `⌘⌥H` | Hide / show instantly |
| `⌘⌥T` | Click-through — type into the editor underneath while still reading |
| `⌘⌥⌫` | Wipe the transcript and current answer |

Rebind any of them under **Settings › Keys**.

### The ask box

The switch to its left picks the engine:

- **Wingman** — NVIDIA NIM. Two or three talking points, sub-second. For
  "what is X", "how would you scale Y".
- **You** — answered only from your stored profile, in first person. For
  "tell me about a time…", "what did you build at…".
- **Screen** — Gemini reads a screenshot and returns a verbal summary, the
  approach, and runnable code with complexity.

### Automatic answers

While listening, xpass transcribes the other side and answers questions as they
land, so you can read while they are still finishing the sentence. It picks the
engine from the question itself:

| Question | Routed to | Why |
|---|---|---|
| "What's wrong with this function?" | **Screen** | a demonstrative pointing at something visible — captures a frame first |
| "Tell me about a time you led a migration" | **You** | past-experience phrasing — answered from your profile |
| "How would you scale this to 10M users?" | **Wingman** | self-contained, answerable from the words alone |

Screen is tested first: a demonstrative names the one resource the other two
tiers cannot see. A bare "implement a queue using two stacks" deliberately does
*not* capture — it is answerable from the words, and a frame would cost a
request and a second of latency for nothing.

Toggle the whole thing with **Answer automatically**, and just the capture half
with **Capture the screen when asked about it**, both under Models.

### Notes

The notes icon in the header keeps every question of the session — heard or
typed — with the tier that answered, the first line of the answer, and its
time-to-first-token. Click an entry to bring that answer back. Cleared by
`⌘⌥⌫` along with everything else.

### How it knows who is talking

By capture path, not by voice. `SYS` is the ScreenCaptureKit system-audio
loopback — anything your speakers play is "them". `MIC` is you. There is no
diarization, so a panel of three interviewers is one undifferentiated "Them".

**Use headphones.** On speakers, their voice re-enters your microphone and
registers on both meters. Mic transcription is off by default, which keeps that
harmless; turning it on while using speakers would transcribe their words as
yours.

### Quitting

xpass has no Dock icon and no menu bar — that is what keeps it out of the app
switcher — so there is no Quit menu item:

| | |
|---|---|
| `⌘Q` | quits, when the HUD has keyboard focus |
| power icon | right of the header; click once to arm, again to quit |
| `⌘⌥H` | hides without quitting, which is usually what you want |
| `pkill -x xpass` | from a terminal, if the HUD is hidden and unfocused |

The two-step on the button is deliberate: it sits beside Panic hide, and
quitting by accident mid-interview would be worse than not being able to quit.

### Moving it

Drag the header. Double-click the header to snap to top centre. The move icon
parks it in any corner. Drag the edges to resize. The droplet icon cycles
opacity; `⎋` closes Settings or hides the HUD.

---

## 4. Your profile

**Settings › You.** Three ways to fill it:

1. **Import from a portfolio.** Reads `/api/about`, `/api/experience` and
   `/api/projects` from the URL you give it. Whatever responds is imported;
   missing endpoints are skipped.
2. **Paste a résumé.** Markdown headings become entries, bullets become talking
   points, and `### Role` under `## Experience` inherits the section.
3. **Type it.** Identity fields plus prepared answers to the common recruiter
   questions.

A prepared answer you write is used as the basis for that question instead of
anything improvised. Retrieval is local keyword scoring over your entries — no
extra API round trip in the latency budget — and only the top matches are sent.

xpass uses **only** facts you stored. If your profile does not cover a question
it says what is adjacent rather than inventing an employer, date or metric you
would then have to defend out loud.

Stored at `~/Library/Application Support/com.xpass.app/profile.json`.

---

## 5. Transcription

The default backend is **Apple's Speech framework, on-device**. Dictation is a
solved problem the OS already does locally, so xpass uses it: no API key, no
network request per sentence, no per-minute quota, and the audio never leaves
the machine. One recogniser per audio source, endpointed on silence, so the
interviewer and you stay on separate transcripts.

If the language pack is installed it runs fully offline; otherwise macOS falls
back to Apple's server-side recogniser, and the Guide tab says which you got.

Cloud alternatives are still selectable under **Settings › Capture** when you
want a specific model's accuracy — Gemini per-utterance, Gemini Live, or your
own NVIDIA Riva NIM container. Those cost a request per sentence and are what
the rate-limit controls below exist for.

## 6. Models

The model dropdowns list each provider's **live catalogue**, fetched from
`generativelanguage.googleapis.com/v1beta/models` and
`integrate.api.nvidia.com/v1/models`. Hardcoded ids go stale fast — the
`gemini-2.0` line is already shut down and the 2.5 line is on its way out.
The hit counter under each picker shows how many came back; the refresh icon
re-fetches. NVIDIA's catalogue is public, so it populates before you add a key.

Static lists in `XpSettings` are offline fallbacks only. Your saved model always
stays selectable even if the provider retires it, so opening Settings never
silently changes it.

---

## 7. If the answer looks like a monologue

Hybrid reasoning models think out loud, and some spend the whole token budget
doing it before writing anything useful. xpass defends against this three ways:

- every NVIDIA request sends `chat_template_kwargs: {thinking: false}` and
  `reasoning_effort: none`, and the system prompt opens with `detailed thinking
  off` — the switch the Nemotron family reads;
- each tier is given one worked example of the answer shape, which suppresses
  preamble far more reliably than instructions alone;
- the stream is filtered before it reaches the HUD: `<think>` blocks are
  stripped, and an untagged opener ("Here's a thinking process:", "Let me think
  through…", "The user is asking…") is discarded. Time-to-first-token is
  measured from the first *useful* token, so the metric is not flattered by
  reasoning the user never saw.

If a response is nothing but reasoning, the panel says so and names the fix
rather than sitting blank. **Switch to a non-reasoning model** under Settings ›
Models — anything with `-instruct` or `-it` in the id is a safe bet; avoid ids
containing `reasoning` or `thinking`.

## 8. Rate limits

This section applies only to the **cloud** transcription backends; the default
on-device one has no quota at all.

On a cloud backend, each thing the other person says is one request, so a fast
exchange can outrun a free-tier quota. xpass paces requests evenly (a leaky
bucket, because bursts are what trip limits), backs off exponentially on HTTP
429, and drops a stale backlog rather than queueing it — an utterance that
lands after the interviewer moved on is worse than no transcript.

If you still hit the limit:

- lower **Requests per minute** under Capture (default 12),
- leave **Transcribe my microphone too** off (default) — it roughly halves the
  request rate, and you already know what you said,
- or use a paid key.

---

## 9. What "invisible" means

`MainFlutterWindow` sets `NSWindowSharingNone`, so the macOS compositor never
hands the surface to a capturing client. The window is absent from the frames
themselves — not painted over — across ScreenCaptureKit, `CGWindowList`,
AVFoundation display capture, and the `getDisplayMedia()` path Zoom, Meet, Teams
and Slack use. Screenshots xpass takes exclude itself, so a solve never captures
its own answer. `LSUIElement` keeps it out of the Dock and app switcher.

It does **not** cover a second camera pointed at your screen, a proctoring tool
that inspects running processes, or anyone watching your eyes.

---

## 10. Layout

```
macos/Runner/
  MainFlutterWindow.swift        sharingType/.none, floating level, transparent frame
  StealthWindowBridge.swift      click-through, opacity, panic hide, geometry
  NativeAudioScreenBridge.swift  ScreenCaptureKit frames + system-audio loopback + mic
  GlobalHotkeyBridge.swift       Carbon RegisterEventHotKey
  SpeechRecognitionBridge.swift  SFSpeechRecognizer, on-device, per source

lib/core/
  constants/      colors, typography, prompt personas
  models/         audio, assist turns, profile, hotkey bindings
  services/       gemini, nvidia_nim, model_catalog, transcription, profile,
                  portfolio_importer, screen_capture, audio_capture, window, settings
  shortcuts/      hotkey registration
  utils/          sse parser, wav encoder, VAD, rate limiter

lib/features/
  hud/            controller + header, streaming markdown, toolbar, ticker
  settings/       guide, models, capture, profile, shortcuts tabs
```

Platform channels: `com.xpass.app/window`, `/media`, `/audio`, `/hotkeys`.

---

## 11. Tests

```bash
flutter test
```

146 tests covering the SSE parser, the VAD state machine and its noise
estimator, WAV framing, profile retrieval and résumé parsing, both model
services against mocked HTTP, the model catalogue, the portfolio importer, the
rate limiter, question routing across the three tiers, the reasoning
filter, transcription-backend selection, settings migration, listen-path
resilience, and answer extraction.

There is no widget-level test: mounting the full HUD tree crashes the test
harness, and a red suite is worse than an honest gap.
