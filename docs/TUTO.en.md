# HOWTO — personal bootc image, A to Z (single doc)

> Replaces: `tuto-bootc`, `tuto-saveurs`, `tuto-complet` (deleted).
> Separate: `memo-bootc` (command cheat-sheet).

## 1. The concept (understand once)

A **bootc** system never updates package by package: it **swaps the
whole disk image**, like switching an app version.

- `/usr` (system) = **read-only**. `sudo dnf install` on it =
  refused or lost at the next reboot.
- `/etc` (configs) and `/var` (data) = **persistent**. Your files
  and settings survive upgrades.
- Each image = a **deployment**. GRUB keeps the old one: if the
  new one doesn't boot, you reboot on the old one (**rollback**).

You never "repair" the running system, you **switch** to an image
that works.

## 2. Check status — `bootc status`

```
bootc status
```

- `booted` = what's running. `staged` = ready for next reboot.
  `rollback` = the parachute.
- Habit: before AND after every operation.

## 3. Update

**Remote image (quay.io, GHCR):**
```bash
sudo bootc upgrade --check
sudo bootc upgrade
reboot
```

**`dnf update --refresh` equivalent (personal image):** no in-place
update — rebuild + switch:
```bash
cd /mnt/DATA/Bootc   # or the project folder
./build.sh localhost/mon-bootc:latest   # fresh base + RPMs (--pull=newer)
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
reboot
```

**Light update (image already on GHCR):** no build, just:
```bash
sudo bootc switch ghcr.io/swam-web/mon-bootc:base-RECENT_CODE
reboot
```
`RECENT_CODE`: GitHub repo → **Packages** → `mon-bootc` →
**Tags** → newest of your flavor.

Separately, as on Fedora: `flatpak update`, and inside each toolbox
`sudo dnf update`.

## 4. Roll back — `bootc rollback` (by heart)

```bash
sudo bootc rollback
reboot
```

Or at boot: GRUB menu → previous entry. Rules:
- Never 2 upgrades/switches without a reboot in between (only one
  previous deployment is kept).
- After a rescuing rollback: `bootc status` to confirm.
- Test rollback ONCE dry so you know it when it counts.

## 5. Switch image — `bootc switch`

```bash
sudo bootc switch quay.io/your/image:tag
reboot
```

**`localhost/` case (local dev):** `bootc upgrade` looks for a
nonexistent local registry (`pinging container registry
localhost/v2`) — normal. Always `switch --transport
containers-storage` (see §3).

**To a VM** (`switch` reads LOCAL storage): build on the host,
transfer, load in the VM:
```bash
# host:
sudo podman save localhost/mon-bootc:latest -o /mnt/DATA/mon-bootc.tar
# transfer: scp, or without SSH: host `python3 -m http.server 8000`
#   in /mnt/DATA, then VM `curl -O http://192.168.122.1:8000/mon-bootc.tar`
# VM:
sudo podman load -i ~/mon-bootc.tar
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
reboot
```

## 6. Re-bake a driver later (no reinstall)

Add the step to the Containerfile, rebuild, transfer, then `switch`
(§3/§5). `/etc` and `/var` survive, only `/usr` is replaced.

## 6b. Switch Fedora version later (e.g. 44 → 45/46)

Hardcoded spots: `FROM ...:44` + COPR URLs (`.../fedora-44/...`).
RPMFusion repos follow automatically (`%fedora` macro).

Steps:
```bash
cd /mnt/DATA/Bootc/Github
git checkout base
# edit Containerfile: FROM ...:44 → :45 + COPR URLs fedora-44 → fedora-45
git add -A && git commit -m "fedora 45" && git push origin base
# 2. Mandatory rebuild + VM test (new kernel, new packages)
./build.sh localhost/mon-bootc:base base
# 3. If VM healthy: transfer + switch + reboot (§3/§5)
#    + merge base into used flavors, push (CI), switch machines
# 4. If broken: rollback (§4), stay on 44 until it matures
```

Never bump blindly: third-party COPRs (kernel, addons) must have
published for the new release, otherwise red build.

## 7. Apps: never `dnf` on the host

| Need | Where |
|---|---|
| Graphical | `flatpak install flathub <name>` |
| CLI / dev | `toolbox` / `distrobox` + dnf inside |
| Personal binary | `~/.local/bin` |
| System service | baked into the image + rebuild + switch |

## 8. Drivers

**Nvidia — 2 ways.** The kmod must match `uname -r` exactly,
otherwise black screen.
- *Baked* (`nvidia` flavor): rebuilt with the kernel, never desyncs.
  Recommended if one machine = one flavor.
- *Post-install* (`install-nvidia-host.sh`): `bootc usr-overlay`
  (transient!) + akmod built against the running kernel +
  `akmods` enabled (auto rebuild on kernel changes).
  Redo after each `bootc upgrade`. Secure Boot OFF or MOK key.
  Check: `nvidia-smi`.

**AMD ROCm** (`install-rocm-host.sh`): userspace only, no kmod
(in-kernel amdgpu) — zero desync risk. Check: `rocminfo`.

**MT7927 WiFi**: always baked (no network at first boot without it).
CachyOS kernel + settings: **untouchable**.

**HP printer**: baked if `printer` flavor, else
`install-hplip-host.sh`. Test: `hp-check -r`.

## 9. Flavors (1 recipe, 4 images)

| Branch / tag | Content | For |
|---|---|---|
| `base` | kernel, MT7927, GNOME, codecs, tools | everywhere, VM |
| `nvidia` | + baked Nvidia driver | RTX host |
| `rocm` | + AMD userspace | AMD PC |
| `printer` | + hplip/gui | printer PC |

The `FLAVOR` file (1 word) says what to build:
```bash
./build.sh localhost/mon-bootc:nvidia nvidia
```

**GitHub CI:** push on a branch ⇒ build of ITS flavor on the
home runner ⇒ image on GHCR (`mon-bootc:<flavor>-<sha>`).
Follow: **Actions** tab (green/red). Rule: work on `base`,
`git merge base` into flavors, never the reverse.

**Runner:** `gh-runner` container (`--privileged`), 1 job at a time.
**Registration** token from the Add runner page (never the PAT).
Logs: `sudo podman logs -f gh-runner`.

## 10. Diagnose

```
journalctl -b -1 -p err | tail -20
journalctl -b -1 | grep -i -E "fail|nvidia|drm|gdm" | tail -30
systemctl --failed
```

- Black after Nvidia update: previous deployment → rerun driver
  script → reboot.
- Red CI build: read the **bottom** of the red step.
- Method: 1 hypothesis, 1 change, 1 reboot, verify.

## 11. Golden rules

> VM first, host second.
> 1 change = 1 reboot = 1 test.
> `bootc status` before and after. Rollback = parachute.
> Local build: `./build.sh`. Recipe: never any secret in it.

## 12. Project cheat-sheet

- Build: `./build.sh [image] [flavor]` (VM, `base` by default).
- ISO: `./build.sh` → `output/*.iso`, test in VM first.
- Host drivers: `install-nvidia-host.sh` / `install-rocm-host.sh` (never in VM).
- Apps: `install-flatpaks.sh` (`WITH_GAMING=1` for games).
- Printer: `install-hplip-host.sh`.
- VM test: see `Test bootc.txt`.
