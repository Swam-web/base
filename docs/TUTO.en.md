# HOWTO — Personal bootc image, A to Z

> **Replaces**: `tuto-bootc`, `tuto-saveurs`, `tuto-complet` (deleted)
> **Complements**: `memo-bootc.html` (command cheat-sheet)

---

## Table of Contents

1. [The concept](#1-the-concept--understand-once)
2. [Check status — `bootc status`](#2-check-status--bootc-status)
3. [Update](#3-update)
4. [Roll back — `bootc rollback`](#4-roll-back--bootc-rollback)
5. [Switch image — `bootc switch`](#5-switch-image--bootc-switch)
6. [Re-bake a driver / Switch Fedora](#6-re-bake-a-driver--switch-fedora)
7. [Apps: never dnf on the host](#7-apps--never-dnf-on-the-host)
8. [Drivers](#8-drivers)
9. [Flavors (1 recipe, 4 images)](#9-flavors--1-recipe-4-images)
10. [Diagnose](#10-diagnose)
11. [Golden rules](#11-golden-rules)
12. [Project cheat-sheet](#12-project-cheat-sheet)

---

## 1. The concept — understand once

A **bootc** system never updates package by package: it **swaps the whole disk image**, like switching an app version.

```
┌─────────────────────────────────────────────────────────────┐
│                    BOOTC SYSTEM                              │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│   /usr  ──── read-only ──── dnf install = REFUSED            │
│                                                               │
│   /etc  ──── persistent ──── configs, services               │
│                                                               │
│   /var  ──── persistent ──── data, home, opt                  │
│                                                               │
│   ┌──────────────────────────────────────────────────────┐   │
│   │  CURRENT DEPLOYMENT (read)                            │   │
│   │  kernel + drivers + apps = 1 atomic layer              │   │
│   └──────────────────────────────────────────────────────┘   │
│                          ▲                                    │
│                          │                                    │
│                    bootc switch                               │
│                          │                                    │
│   ┌──────────────────────────────────────────────────────┐   │
│   │  NEW DEPLOYMENT (staged)                              │   │
│   │  ready for next reboot                                │   │
│   └──────────────────────────────────────────────────────┘   │
│                          ▲                                    │
│                          │                                    │
│                      ROLLBACK                                 │
│                    (parachute)                                │
│                                                               │
└─────────────────────────────────────────────────────────────┘

  Image = complete snapshot. You never repair, you SWITCH.
```

### Fundamental rule

| What you do | Result |
|---|---|
| `sudo dnf install something` | Lost on reboot (on /usr) |
| Edit `/etc/nginx/nginx.conf` | ✅ Persists |
| Save in `/home/` or `/mnt/data/` | ✅ Persists |
| `bootc rollback` | Full rollback |

---

## 2. Check status — `bootc status`

```bash
bootc status
```

Typical output:

```
Deployments:
 ● ostree-image-signed:quay.io/.../mon-bootc:base
     Version: 44.20260913.0 (2026-09-13T18:22:00Z)
     Booted: yes

  ostree-image-signed:quay.io/.../mon-bootc:base
     Version: 44.20260912.0 (2026-09-12T18:22:00Z)
     Booted: no  ← ROLLBACK possible
```

| Field | Meaning |
|---|---|
| `Booted: yes` | What's running now |
| Deployment without `Booted` | Staged (next reboot) or rollback |
| `rollback` | The parachute — only one kept |

> ⚡ **Habit**: `bootc status` before AND after every operation.

---

## 3. Update

### Remote image (quay.io, GHCR)

```bash
sudo bootc upgrade --check     # check without applying
sudo bootc upgrade            # download + stage
reboot                        # switch
```

### Personal image (this project's case)

No in-place update — rebuild + switch:

```bash
cd /mnt/DATA/Bootc/Github    # or your project folder
./build.sh localhost/mon-bootc:latest    # fresh rebuild
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
reboot
```

### Light update (image already on GHCR)

No build, just change tag:

```bash
sudo bootc switch ghcr.io/swam-web/mon-bootc:base-<RECENT_CODE>
reboot
```

Where to find `RECENT_CODE`:
> GitHub repo → **Packages** tab → `mon-bootc` → **Tags** → newest

### Separately, as on current Fedora

```bash
flatpak update                         # graphical apps
toolbox enter → sudo dnf update        # dev env (container)
```

---

## 4. Roll back — `bootc rollback`

```bash
sudo bootc rollback
reboot
```

Or at boot: GRUB menu → previous entry.

```
  BEFORE:  booted = deployment A
  bootc rollback
  REBOOT  → booted = previous deployment B
```

> ⚠️ **Rules**:
> - Never 2 switches without reboot in between (only 1 rollback kept)
> - After a rescuing rollback: `bootc status` to confirm
> - **Test rollback ONCE dry** so you know the drill when it matters

---

## 5. Switch image — `bootc switch`

```bash
sudo bootc switch quay.io/<REGISTRY>/<IMAGE>:<TAG>
reboot
```

### `localhost/` case (local dev) ⚠️

`bootc upgrade` with a `localhost/` image fails:

```
error: pinging container registry localhost/v2: ...
```

This is normal: no local registry. Use **switch** with explicit transport:

```bash
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
```

### To a VM (switch reads LOCAL storage)

```
┌──────────────────┐                    ┌──────────────────┐
│      HOST        │                    │       VM         │
│                  │                    │                  │
│  podman save ─────┼─── transfer ────┼──► podman load   │
│                  │    (scp/http)     │                  │
│                  │                    │  bootc switch    │
│                  │                    │  --transport     │
│                  │                    │  containers-     │
│                  │                    │  storage         │
└──────────────────┘                    └──────────────────┘
```

```bash
# On host:
sudo podman save localhost/mon-bootc:latest -o /mnt/DATA/mon-bootc.tar

# Transfer (your choice):
scp /mnt/DATA/mon-bootc.tar user@vm:~/            # via SSH
# OR without SSH:
#   host: cd /mnt/DATA && python3 -m http.server 8000
#   VM:   curl -O http://192.168.122.1:8000/mon-bootc.tar

# In VM:
sudo podman load -i ~/mon-bootc.tar
sudo bootc switch --transport containers-storage localhost/mon-bootc:latest
reboot
```

---

## 6. Re-bake a driver / Switch Fedora

### Re-bake (add a driver to Containerfile)

```
  Modified Containerfile
       │
       ▼
  ./build.sh localhost/mon-bootc:new
       │
       ▼
  bootc switch → reboot
       │
       ▼
  /usr replaced, /etc + /var survive
```

1. Add step in `Containerfile`
2. Rebuild, transfer, `switch` (§3/§5)
3. `/etc` and `/var` survive — only `/usr` is replaced

### Switch Fedora version (44 → 45/46)

What's "hardcoded" in Containerfile:

| Element | Example |
|---|---|
| FROM | `FROM quay.io/fedora/fedora-bootc:44` |
| COPR | `.../fedora-44/bieszczaders-kernel-...` |

Steps:

```bash
cd /mnt/DATA/Bootc/Github
git checkout base

# Edit Containerfile:
#   FROM ...:44  →  FROM ...:45
#   COPR URLs → fedora-45 versions

git add -A && git commit -m "fedora 45" && git push origin base

# Rebuild + VM test MANDATORY (new kernel, new packages)
./build.sh localhost/mon-bootc:base base

# If VM healthy:
#   transfer + switch + reboot (§3/§5)
#   + merge base into used flavors, push (CI), switch machines

# If broken:
#   rollback (§4), stay on 44 until it matures
```

> 🚨 **NEVER bump blindly**: third-party COPRs (CachyOS kernel, addons)
> must have published for the new release, otherwise red build.

---

## 7. Apps: never dnf on the host

```
  ┌─────────────────────────────────────────────────────────┐
  │                    HOST (bootc)                          │
  │                                                         │
  │   /usr  = read-only  →  NO dnf install                 │
  │                                                         │
  │   Apps on top:                                         │
  │   ┌─────────────┐  ┌─────────────┐  ┌──────────────┐  │
  │   │  Flatpak    │  │  Toolbox /  │  │  ~/.local/   │  │
  │   │  (Flathub)  │  │  Distrobox  │  │  bin/        │  │
  │   │             │  │  (Fedora)   │  │  (Personal)  │  │
  │   └─────────────┘  └─────────────┘  └──────────────┘  │
  │                                                         │
  │   System service = baked into image (rebuild)          │
  └─────────────────────────────────────────────────────────┘
```

| Need | Where | Command |
|---|---|---|
| Graphical | Flatpak (Flathub) | `flatpak install flathub <name>` |
| CLI / dev | Toolbox / Distrobox | `toolbox enter` → `sudo dnf install` |
| Personal binary | `~/.local/bin` | `./my-app` |
| System service | In image | Rebuild + switch |

---

## 8. Drivers

### Nvidia — 2 ways

Nvidia driver **must** match `uname -r` exactly, otherwise black screen.

```
  ┌─────────────────────────┐     ┌─────────────────────────┐
  │   WAY A: BAKED          │     │   WAY B: POST-INSTALL   │
  │   (nvidia flavor)       │     │   (host script)         │
  │                         │     │                         │
  │   Containerfile:        │     │   install-nvidia-       │
  │   FROM + akmod-nvidia   │     │   host.sh               │
  │   compiled with kernel  │     │   bootc usr-overlay      │
  │                         │     │   (transient!)           │
  │   ✅ Never desyncs      │     │   ⚠️ Redo after each    │
  │   ✅ Rebuild = aligned  │     │     upgrade             │
  │   ⚠️ Heavy (~2 Go)      │     │   ✅ Lightweight         │
  └─────────────────────────┘     └─────────────────────────┘
```

```bash
# Verify:
nvidia-smi

# Secure Boot: kmods unsigned Fedora key
#   → disable Secure Boot OR enroll MOK key
```

### AMD ROCm (install-rocm-host.sh)

Userspace only, no kmod (amdgpu in-kernel) — **zero desync risk**.

```bash
rocminfo    # verify
```

### MT7927 WiFi — always baked

No network at first boot without it. Firmware + driver in image.

### HP printer

```
  printer flavor → hplip + hplip-gui baked
  other flavor   → install-hplip-host.sh (post-install)
```

Test: `hp-check -r`

> ⚠️ **CachyOS kernel + settings = untouchable**. Never modify
> without prior VM testing.

---

## 9. Flavors (1 recipe, 4 images)

```
                        ┌──────────────────────────────┐
                        │      Containerfile           │
                        │   (1 single recipe)          │
                        │   + build-args (3 flags)     │
                        └──────────┬───────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
    ┌─────────▼──────┐  ┌─────────▼──────┐  ┌─────────▼──────┐
    │   WITH_NVIDIA  │  │   WITH_ROCM    │  │  WITH_PRINTER  │
    │       =1       │  │      =1        │  │      =1        │
    └─────────┬──────┘  └─────────┬──────┘  └─────────┬──────┘
              │                    │                    │
    ┌─────────▼──────┐  ┌─────────▼──────┐  ┌─────────▼──────┐
    │    nvidia      │  │     rocm       │  │    printer     │
    │  (RTX host)    │  │   (AMD host)   │  │  (printer)     │
    └────────────────┘  └────────────────┘  └────────────────┘

           all : CachyOS kernel + MT7927 + GNOME + codecs
```

| Branch | Content | For |
|---|---|---|
| `base` | kernel, MT7927, GNOME, codecs, tools | everywhere, VM |
| `nvidia` | + baked Nvidia driver | RTX host |
| `rocm` | + AMD userspace | AMD PC |
| `printer` | + hplip/gui | printer PC |

### Build

```bash
./build.sh localhost/mon-bootc:nvidia nvidia
```

The `FLAVOR` file (1 word) in `build/` sets the default flavor.

### GitHub CI

```
  push on branch
       │
       ▼
  ┌─────────────────────────────────────────────┐
  │  Actions (workflow build.yml)               │
  │                                             │
  │  4 parallel jobs:                           │
  │    build-base / build-nvidia /              │
  │    build-rocm   / build-printer             │
  │                                             │
  │  → podman build → local image              │
  │  → bootc-image-builder → ISO in output/     │
  └─────────────────┬───────────────────────────┘
                    │
                    ▼
              ghcr.io/swam-web/mon-bootc:<flavor>-<sha>
```

> 📌 **Git rule**: work on `base`, `git merge base` into flavors, **never reverse**.

---

## 10. Diagnose

```bash
# Previous boot errors
journalctl -b -1 -p err | tail -20

# Targeted filter
journalctl -b -1 | grep -i -E "fail|nvidia|drm|gdm" | tail -30

# Failed services
systemctl --failed
```

| Symptom | Solution |
|---|---|
| Black after Nvidia update | Boot previous deployment → rerun `install-nvidia-host.sh` → reboot |
| Red CI build | Read the **bottom** of the red step in logs |
| General | 1 hypothesis → 1 change → 1 reboot → verify |

---

## 11. Golden rules

```
  ╔═══════════════════════════════════════════════════════╗
  ║  1. VM first, host second                             ║
  ║  2. 1 change = 1 reboot = 1 test                      ║
  ║  3. bootc status before and after                     ║
  ║  4. Rollback = parachute (test it dry)                ║
  ║  5. Local build: ./build.sh (never any secret)        ║
  ╚═══════════════════════════════════════════════════════╝
```

---

## 12. Project cheat-sheet

```bash
# Build ISO (test in VM first)
./build.sh [image] [flavor]

# Host (never in VM)
sudo install-nvidia-host.sh      # Nvidia
sudo install-rocm-host.sh        # AMD
sudo install-hplip-host.sh       # Printer
sudo install-flatpaks.sh         # Apps (+ WITH_GAMING=1)
```

See also: `docs/test-vm.md` for complete VM testing procedure.

---

<p align="center"><em>Document maintained with care. Bootc = peace of mind.</em></p>
