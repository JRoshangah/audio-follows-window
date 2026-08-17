# Troubleshooting

Most problems here are **not** with this script. On many Intel laptops, getting
a second audio sink to exist and stay working is the hard part.

Work through the ladder below in order. It goes from the software layer down
to the hardware, and each step tells you whether to keep descending.

## The diagnostic ladder

When there's no sound, find out *how far down* the audio is getting.

### 1. Is the stream on the sink you expect?

```bash
pactl list sinks short
pactl list sink-inputs | grep -E "Sink Input #|Sink:|Corked:|application.name"
```

Match the stream's `Sink:` number against the sink list. If it's on the wrong
one, this is a routing problem: see [Audio goes to the wrong
display](#audio-goes-to-the-wrong-display). `Corked: yes` just means the stream
is paused; that's normal.

### 2. Is the sink receiving data?

```bash
pactl list sinks | grep -B2 -A10 "Name: YOUR_SINK" | grep -E "Sink #|State:|Name:"
```

`RUNNING` means data is arriving. `IDLE` with something actively playing means
the app isn't sending. Check that it isn't paused or muted.

`State:` appears *above* `Name:` in pactl's output, which is why the grep needs
`-B2`. Getting this wrong makes the state silently disappear from your results.

### 3. Is ALSA receiving data?

```bash
cat /proc/asound/card0/pcm3p/sub0/status
```

Adjust `pcm3p` to your device number: `pcm<N>p` for `hw:0,N`. You want
`state: RUNNING` and an `hw_ptr` that increases between runs.

If so, PipeWire is successfully writing to the hardware and **the problem is
below the software stack entirely**. Skip to step 5.

### 4. Is the monitor detected?

```bash
for f in /proc/asound/card0/eld#*; do
  grep -q "eld_valid.*1" "$f" && { echo "== $f"; grep -E "monitor_present|eld_valid|monitor_name" "$f"; }
done
```

Exactly one pin should report `eld_valid 1` with your monitor's model name.
If none do, the display isn't advertising audio over EDID.
Could be a bad cable, a
passive DisplayPort adapter, or a monitor with no speakers.

These files are named `eld#<codec>.<pin>`, **not** `eld#<card>.<device>`. The
numbers won't match your `hw:0,N` device, and that's expected. Don't go looking
for a renumbered device because these don't line up.

### 5. Is the digital output switch muted?

```bash
amixer -c 0 scontents | grep -B4 -i "playback \[off\]"
```

See the next section. This is the most common cause and the hardest to spot.

## Sink exists, state RUNNING, but no sound

**Cause:** the `IEC958` playback switch for that HDMI pin is muted.

These are per-pin digital output switches that live below PulseAudio, so
`pactl` reports the sink at 100% and unmuted while ALSA silently discards
everything. Every software layer looks healthy. `paplay` exits successfully.
There is no error anywhere.

Find it:

```bash
amixer -c 0 scontents | grep -B4 -i "playback \[off\]"
```

Fix it:

```bash
amixer -c 0 sset "IEC958",0 on
```

The trailing number is the control index. A card may have several, and only
one corresponds to your active pin. Turning all of them on is harmless:

```bash
for i in 0 1 2 3 4 5; do amixer -c 0 sset "IEC958",$i on 2>/dev/null; done
```

### Making it survive reboot

`sudo alsactl store` does **not** reliably hold. When the active card profile
is analog-only, ACP re-mutes the HDMI pin at every boot on the assumption that
nothing needs it, and it wins the race against restored state.

The fix is to unmute as a service prerequisite, which runs after ALSA settles.
The shipped unit file does this:

```ini
ExecStartPre=/usr/bin/amixer -c 0 sset IEC958,0 on
```

Adjust `-c 0` and the control index for your hardware. On a machine where they
don't apply, it fails and the service starts anyway.

Confirm it fired:

```bash
systemctl --user status audio-follows-window
```

Look for `ExecStartPre=... (code=exited, status=0/SUCCESS)` and a
`Mono: Playback [on]` line in the log output.

## Only one sink shows up

Common on Intel laptops. Check your card profiles:

```bash
pactl list cards | grep -A40 "Profiles:"
```

If every profile says `sinks: 1`, no profile exposes analog and HDMI at the
same time. Switching profiles would swap outputs, not add one.

Confirm the HDMI hardware exists:

```bash
aplay -l | grep -i hdmi
```

A line like `card 0: PCH, device 3: HDMI 0 [HG556J02]` means the monitor's EDID
name was read, so it's connected and advertises audio. That's `hw:0,3`.

Copy `examples/10-hdmi-sink.conf` to `~/.config/pipewire/pipewire.conf.d/`,
edit `api.alsa.path` to match, then:

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
```

This works because the active card profile doesn't claim that PCM, so the
static node grabs it without fighting WirePlumber. Keep analog with full
jack detection *and* get a second sink.

The `pro-audio` profile is an alternative one-liner that exposes every PCM at
once, but it bypasses the ACP layer, so headphone jack detection stops working.

## Don't touch the profile dropdown

Once you're using a static node, **leave the hardware profile alone** in Sound
Preferences.

Changing it makes ACP try to claim the same PCM your static node holds. The two
collide, the node loses its device handle, and it stays in the graph looking
perfectly healthy while routing audio nowhere. Reverting the profile does not
help. Nothing re-creates a static node except a daemon restart:

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
```

Symptom in the log:

```
spa.alsa: 'hw:0,3': playback open failed: Device or resource busy
mod.adapter: can't get format: Device or resource busy
```

Check with `journalctl --user -u pipewire -n 30 --no-pager`.

These lines are timestamped, and an old failure stays in the log long after the
problem is gone. Check the timestamp.
will send you after a device conflict that no longer exists.

## Audio goes to the wrong display

PulseAudio remembers where each app was last sent and restores that on
launch, regardless of where the window is. You'll see
`module-stream-restore.id` in the stream properties.

Since routing only fires on an actual *move*, a window that opens on the wrong
display keeps the remembered sink indefinitely. Drag it back and forth once, or
run `audio-follows-window --once` with it focused.

## Routing stops working in one direction

Check that the sink names in your config still exist:

```bash
pactl list sinks short
audio-follows-window --list
```

PipeWire sometimes appends a numeric suffix after a restart:
`...analog-stereo` becoming `...analog-stereo.3`. Your config still holds the
old name, so moves to that display fail with `No such entity` while the other
direction keeps working.

Re-run `audio-follows-window --setup` to pick up the current names.

## Nothing happens when I drag

Run with `-v`. No output at all usually means `xdotool` isn't returning a
window:

```bash
xdotool getactivewindow getwindowgeometry
```

If that fails, you're on Wayland, or your window manager doesn't set
`_NET_ACTIVE_WINDOW`.

If the service is running rather than a foreground `--watch`, note that Python
block-buffers stdout when it isn't a TTY, so `journalctl` may look empty even
when the script is working normally.

## `speaker-test` says Device or resource busy

Expected. PipeWire holds the device, so `speaker-test -D hw:0,3` can't open it.
That test only works with PipeWire stopped.

Use `paplay` instead:

```bash
paplay -d hdmi_monitor /usr/share/sounds/alsa/Front_Center.wav
```


## Autostart without systemd

Some MATE and XFCE sessions don't reliably reach `graphical-session.target`, so
the user unit never fires. Check after a reboot:

```bash
systemctl --user status audio-follows-window
```

If it didn't start, use the desktop's own autostart instead:

```bash
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/audio-follows-window.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Audio Follows Window
Exec=%h/.local/bin/audio-follows-window --watch
X-GNOME-Autostart-enabled=true
EOF
systemctl --user disable audio-follows-window
```

This loses the `ExecStartPre` unmute. If you need it, point `Exec=` at a
wrapper script that runs `amixer -c 0 sset IEC958,0 on` first.

## Uninstalling

`install.sh` writes to three places outside the repo, so deleting the checkout
does not uninstall:

```bash
systemctl --user disable --now audio-follows-window
rm -f ~/.config/systemd/user/audio-follows-window.service
rm -f ~/.local/bin/audio-follows-window
systemctl --user daemon-reload
```

Verify with `which audio-follows-window`: silence means it's gone.

Two files are deliberately left behind:

- `~/.config/audio-follows-window/config.ini`: your display mapping. Remove it
  if you want `--setup` to start fresh.
- `~/.config/pipewire/pipewire.conf.d/10-hdmi-sink.conf`: not part of this
  program. Removing it takes your second sink away.

## Wayland

Not supported. Each compositor needs its own
approach: `swaymsg -t get_tree` on wlroots, a KWin script on KDE, a shell
extension on GNOME. Contributions welcome.
