# audio-follows-window

Drag a window to another monitor, and that app's audio follows it.

While watching the focused X11 window, when you drop that window on a different display, any
audio streams belonging to that app move to the sink mapped to that display.

## Install

```bash
git clone https://github.com/JRoshangah/audio-follows-window.git
cd audio-follows-window
./install.sh
audio-follows-window --setup
```

`--setup` lists your displays and audio sinks and asks you to pair them. It
writes `~/.config/audio-follows-window/config.ini`

Confirm it works before enabling the service:

```bash
audio-follows-window --watch -v
```

Play something, drag the window across, and you should see a line like
`Chromium -> HDMI-1 (hdmi_monitor)`. Then:

```bash
systemctl --user enable --now audio-follows-window
```

## Requirements

- **X11.** Wayland compositors don't expose window geometry to unprivileged
  clients, so `xdotool` can't see anything. See "Wayland" below.
- `xdotool`, `xprop`, `xrandr`: `sudo apt install xdotool x11-utils x11-xserver-utils`
- `pactl` with JSON support: PulseAudio 16+ or any pipewire-pulse
- Python 3.8+, standard library only

## Usage

| Command | What it does |
| --- | --- |
| `--setup` | Interactively map displays to sinks |
| `--watch` | Run continuously (default) |
| `--list` | Print detected monitors and sinks |
| `--once` | Route the focused window right now |
| `-v` | Log each stream move |

`--once` is useful for windows that were already sitting on a display before
the daemon started: routing only fires on an actual move, so those get skipped
until you move them.

## Config

```ini
[monitors]
eDP-1 = alsa_output.pci-0000_00_1f.3.analog-stereo
HDMI-1 = hdmi_monitor

[settings]
poll_seconds = 0.3
```

Keys are `xrandr` output names, values are `pactl` sink names. Get both from
`--list`. Displays you leave out fall back to crude name matching, which is
unreliable with more than two sinks.

## How it works

**Drag detection.** The window rect is compared against the previous tick. If
it changed, the window is still moving and nothing happens. Audio only switches
once geometry holds still.

**Which app owns the audio.** Chrome's audio service and Firefox's content
processes have different PIDs than the window, so matching `_NET_WM_PID`
against `application.process.id` finds nothing. The script walks `/proc` to
collect every descendant of the window's PID and matches any stream in that
set.

**Which display a window is on.** Overlap area, not corner position. A window
between two monitors belongs to whichever holds more of it.

## Known limitation: browser tabs

Chromium routes **all** tabs through a single audio service process. Moving a
Chrome window moves every Chrome tab's audio with it. Firefox splits audio
across content processes and often behaves per-window, but not reliably.

Per-tab routing would need a browser extension using `chrome.tabCapture` and
`AudioContext.setSinkId()`. Out of scope here.

## Troubleshooting

### Only one sink shows up

Common on Intel laptops. Check your card profiles:

```bash
pactl list cards | grep -A40 "Profiles:"
```

If every profile says `sinks: 1`, no profile exposes analog and HDMI at the
same time. Switching profiles would swap outputs, not add one. Confirm the
HDMI hardware exists:

```bash
aplay -l | grep -i hdmi
```

A line like `card 0: PCH, device 3: HDMI 0 [HG556J02]` means the monitor's
EDID name was read, so it's connected and advertises audio. That's `hw:0,3`.

Copy `examples/10-hdmi-sink.conf` to
`~/.config/pipewire/pipewire.conf.d/`, edit `api.alsa.path` to match, then:

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
```

This works because the active card profile doesn't claim that PCM, so the
static node grabs it without fighting WirePlumber.

The `pro-audio` profile is an alternative one-liner that exposes every PCM at
once, but it bypasses the ACP layer, so headphone jack detection stops working.

### Sink exists but no sound

1. Run `alsamixer -c 0`: press F6, select the card, unmute any `S/PDIF` / `IEC958`
   channel with `M`
2. Add `audio.rate = 48000` to the drop-in; some HDMI PCMs reject the default
3. Check the monitor's own OSD volume and input source
4. `paplay -d SINKNAME /usr/share/sounds/alsa/Front_Center.wav` to test directly

`speaker-test -D hw:0,3` returning `-16 Device or resource busy` is expected since
PipeWire holds the device. That test only works with PipeWire stopped.

### Autostart without systemd

Some MATE and XFCE sessions don't reliably reach `graphical-session.target`,
so the user unit never fires. Use the desktop's own autostart instead:

```bash
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/audio-follows-window.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Audio Follows Window
Exec=%h/.local/bin/audio-follows-window --watch
X-GNOME-Autostart-enabled=true
EOF
```

MATE users can also add it through **Startup Applications** in the menu.

### Nothing happens when I drag

Run with `-v`. No output at all usually means `xdotool` isn't returning a
window. Check `xdotool getactivewindow getwindowgeometry`. If that fails,
you're on Wayland.

### Wayland

Not supported. Each compositor needs its own
approach: `swaymsg -t get_tree` on wlroots, a KWin script on KDE, a shell
extension on GNOME. Contributions welcome.

## License

MIT
