# systemd units — weekly smoke (examples, Ubuntu on the Sparks)

Automates doc 04 §3's weekly cadence and checks doc 07 Level 3's
"Monitoring: weekly smoke automated ... with a notification path" box.

These are EXAMPLES written before hardware existed: the paths and `User=`
inside `vr-smoke.service` are guesses — edit them to the real kit checkout
before install. Install on the gateway node (Spark A).

## Install

```bash
# 1. EDIT vr-smoke.service first: WorkingDirectory / EnvironmentFile /
#    ExecStart paths + User=. Port in ExecStart too if GATEWAY_PORT != 4000.
sudo cp ops/systemd/vr-smoke.service ops/systemd/vr-smoke.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vr-smoke.timer
```

## Test now (don't wait a week)

```bash
sudo systemctl start vr-smoke.service   # runs the smoke once
systemctl status vr-smoke.service       # exit 0 = nothing answered WRONG (see below)
journalctl -u vr-smoke.service -n 50    # smoke.sh PASS/FAIL lines live here
systemctl list-timers vr-smoke.timer    # next fire scheduled?
```

Exit code is smoke.sh's own gate: nonzero = a route answered in the WRONG
shape. But an unreachable route prints `....` and still exits 0 — intentional
for on-demand fleet, which means a silently-down brain/coder also passes the
exit code. Read the journal lines, not just the code; if that bites, tighten
smoke.sh — don't paper over it here.

## Notification path (operator supplies — the timer is useless without one)

`OnFailure=vr-notify@%n.service` fires on any nonzero run. The notify unit
is yours to supply — the kit won't pick your channel. Template
(`/etc/systemd/system/vr-notify@.service`), ntfy shown; swap in Slack
webhook / mail as you like:

```ini
[Unit]
Description=Failure notify for %i

[Service]
Type=oneshot
# EDIT: your channel/topic.
ExecStart=/usr/bin/curl -fsS -d "%i failed on %H" https://ntfy.sh/<topic>
```

No notify unit yet? Delete the `OnFailure=` line rather than referencing a
unit that doesn't exist — but a silent FAIL defeats the point of the timer
(doc 04 §3: "alert on any FAIL").

Weekly smoke results land on the evidence pages like any other gate run
(`ops/evidence/`); a FAIL triggers the doc 04 matrix row for whatever
changed underneath it.
