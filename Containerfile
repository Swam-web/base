# Containerfile — Fedora 44 bootc + kernel CachyOS latest 7.2.x + MT7927 DKMS
# (Nvidia post-install host, voir install-nvidia-host.sh)
#
# Base : quay.io/fedora/fedora-bootc:44 (stable depuis avril 2026)
# Kernel : kernel-cachyos depuis COPR bieszczaders/kernel-cachyos (latest 7.2.x)
#   -> 7.2.5-cachyos1 vérifiée présente depuis le 13/09/2026 (miroir CachyOS).
#      On prend la dernière dispo au moment du build, pas de pin exact.
# Nvidia : HORS IMAGE, voir install-nvidia-host.sh (post-install host).
# WiFi/BT : jetm/mediatek-mt7927-dkms pinné v2.14-6, méthode bazzite-mt7927
#   -> MT7927 Filogic 380 WiFi 7 + MT6639 BT. En 7.2 le driver est in-tree,
#      le paquet apporte firmware BT + 4 patches AP-mode + 1 ID BT.
#      Firmware WiFi vient de linux-firmware (pas du ZIP, pour ne pas shadower).
#
# Sécurité (primée) :
# - Versions pinnées + sha256 vérifiés (kernel tarball, ZIP ASUS).
# - Pas de `make download` aveugle : vérif sha256 avant `make sources`.
# - Outils de build nettoyés après, /tmp vidé, pas de secret embarqué.
# - Secure Boot : kmods akmod/dkms non signés clé Fedora → désactivez
#   Secure Boot ou enrolez votre clé MOK, sinon écran noir / fallback nouveau.
# - Ne jamais tester l'ISO sur disque hôte, toujours en VM d'abord.
# - Pas de clearpart/autopart ici : l'interactivité est gérée par config.toml.
#
# SOMMAIRE (familles) :
#   A. NOYAU ............ étape 1 (+ rebuild final 17)
#   B. PILOTES .......... étape 3 MT7927 (Nvidia : post-install host)
#   C. SYSTÈME .......... étape 4 base+snapper
#   D. MULTIMÉDIA ....... étapes 5 codecs, 6 AppImage/Flatpak
#   E. ADDONS CACHYOS ... étape 7
#   F. GAMING ........... étapes 8 stack, 12 réglages
#   G. BUREAU GNOME ..... étapes 9 gestion, 10 bureau, 14 réglages
#   H. OPTIMISATIONS .... étapes 11 hardware, 13 divers, 15 audio/réseau/sécu, 16 finitions, 17 final
#   I. OUTILS & TERMINAL  étapes 18 parité, 19 zsh, 20 omz/p10k

FROM quay.io/fedora/fedora-bootc:44

# SAVEURS (build-args, défaut 0 = base) :
#   WITH_NVIDIA=1  -> pilote Nvidia RPMFusion baké (rebuild ensemble => pas de désync)
#   WITH_ROCM=1    -> userspace AMD ROCm (sans kmod, safe)
#   WITH_PRINTER=1 -> hplip + hplip-gui bakés
# WiFi MT7927 toujours inclus (base) : pas de réseau sans lui au 1er boot.
ARG WITH_NVIDIA=0
ARG WITH_ROCM=0
ARG WITH_PRINTER=0

# ######################################################################
# A. NOYAU — étape 1
# ######################################################################
# 1. COPR kernel CachyOS + remplacement du kernel Fedora
# On reste en GCC (pas LTO) pour que les builds DKMS/akmods compilent sans clang.
RUN <<EORUN
set -xeuo pipefail
# Repo COPR CachyOS (F44)
curl -L -o /etc/yum.repos.d/bieszczaders-kernel-cachyos-fedora-44.repo \
  https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/repo/fedora-44/bieszczaders-kernel-cachyos-fedora-44.repo
# Nettoie les vieux kernels du base image pour éviter les doublons /boot
dnf -y remove kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra || true
rm -rf /usr/lib/modules/*
# Installe dernier kernel-cachyos 7.2.x + headers (requis pour DKMS MT7927)
dnf -y install kernel-cachyos kernel-cachyos-devel-matched
# Force vmlinuz au chemin attendu par bootc/rpm-ostree
NEW_KVER=$(ls /usr/lib/modules | grep -i cachy | sort -V | tail -1)
echo "Kernel CachyOS installé : $NEW_KVER"
if [ ! -f "/usr/lib/modules/${NEW_KVER}/vmlinuz" ] && [ -f "/boot/vmlinuz-${NEW_KVER}" ]; then
  cp "/boot/vmlinuz-${NEW_KVER}" "/usr/lib/modules/${NEW_KVER}/vmlinuz"
fi
# Initramfs complète pour déploiement ostree/bootc (pas hostonly)
# Fix connu bootc (Bluefin/Bazzite) : /root est un lien vers /var/roothome absent au build,
# dracut le suit et échoue avec "ERROR: installing '/root'". Créé une fois ici, persisté en couches.
mkdir -p /var/roothome
dracut --reproducible --no-hostonly --add "ostree" --force "/usr/lib/modules/${NEW_KVER}/initramfs.img" "${NEW_KVER}"
rm -rf /boot/*
# Day-2 bootc : /opt immutable lié vers /var/opt AVANT tout install (reco bootc officielle)
rm -rf /opt || true
ln -s /var/opt /opt || true
mkdir -p /var/opt
dnf clean all
EORUN

# ######################################################################
# B. PILOTES — étape 3 MT7927 (Nvidia volontairement hors image :
# installé post-install sur host via install-nvidia-host.sh)
# ######################################################################
# 3. MT7927 DKMS (jetm v2.14-6) + firmware BT — sécurité d'abord
# Réf : https://github.com/jetm/mediatek-mt7927-dkms + https://github.com/samutoljamo/bazzite-mt7927
RUN <<EORUN
set -xeuo pipefail
dnf -y install dkms git curl python3 patch xz linux-firmware kernel-cachyos-devel-matched
KVER=$(ls /usr/lib/modules | grep -i cachy | sort -V | tail -1)
echo "DKMS MT7927 pour kernel : $KVER"
MT7927_TAG="v2.14-6"
MT7927_VER="2.14"
# Clone pinné, pas master flottant
git clone --depth 1 --branch "$MT7927_TAG" https://github.com/jetm/mediatek-mt7927-dkms.git /tmp/mt7927
grep -q 'PACKAGE_VERSION="2.14"' /tmp/mt7927/dkms.conf
grep -q "pkgver=2.14" /tmp/mt7927/PKGBUILD
cd /tmp/mt7927
# Télécharge tarball kernel 7.2 + ZIP driver ASUS (source BT firmware)
make download
# Vérif sha256 pinnées depuis PKGBUILD upstream (vérifié le 15/09/2026)
echo "f9fef3d14c0df53819026f4be74459835c2a0b0dcbf5b5bbd9ea19f0829402b3  linux-7.2.tar.xz" | sha256sum -c -
echo "b377fffa28208bb1671a0eb219c84c62fba4cd6f92161b74e4b0909476307cc8  DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R.zip" | sha256sum -c -
make sources
make install
# Build + install DKMS contre kernel CachyOS (BT skippé auto en 7.2 sauf BUILD_BT=yes)
dkms add "mediatek-mt7927/${MT7927_VER}"
dkms build "mediatek-mt7927/${MT7927_VER}" -k "$KVER"
dkms install "mediatek-mt7927/${MT7927_VER}" -k "$KVER"
dkms status
# Vérifs : modules WiFi DKMS + firmware BT, WiFi firmware depuis linux-firmware
ls -l "/usr/lib/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin"
# Chemin variable selon distro (extra/ sur Fedora, updates/dkms/ ailleurs) : modinfo fait foi
# -k obligatoire : par défaut modinfo vise le kernel hôte du build, pas le CachyOS embarqué
modinfo -n -k "$KVER" mt7925e
modinfo -n -k "$KVER" mt7925e | grep -q "$KVER" || (echo "kmod mt7925e manquant pour $KVER"; exit 1)
ls /usr/lib/firmware/mediatek/mt7927/ | head -20
# Initramfs avec nouveaux modules
dracut --reproducible --no-hostonly --add "ostree" --force "/usr/lib/modules/${KVER}/initramfs.img" "${KVER}"
rm -rf /boot/* /tmp/mt7927 /tmp/* /var/tmp/*
# Outils CONSERVÉS : git ressert étape 20, patch/xz sont vitaux
# (dracut, bootc, ostree, akmods, dkms en dépendent).
# Un remove large avait arraché bootc, ostree, dracut, akmods, dkms et clevis-dracut : plus jamais.
dnf clean all
EORUN

# 3b. ROCm userspace AMD (optionnel, WITH_ROCM=1) — SANS kmod :
# amdgpu in-kernel, aucun risque de désync (contrairement à Nvidia).
RUN <<EORUN
set -xeuo pipefail
if [ "${WITH_ROCM:-0}" = "1" ]; then
  dnf -y install rocminfo rocm-runtime rocm-hip-runtime rocm-opencl-runtime \
    || dnf -y install rocminfo rocm-runtime \
    || { echo "ROCm indisponible dans les repos"; exit 1; }
  command -v rocminfo
fi
echo "ROCm: WITH_ROCM=${WITH_ROCM:-0} (0=sans, 1=avec)"
dnf clean all
EORUN

# ######################################################################
# C. SYSTÈME — étape 4 base + snapper
# ######################################################################
# 4. Base système minimale bootc + Snapper / Btrfs Assistant
# Vérifié : snapper-0.13.0-3.fc44 et btrfs-assistant-2.2-6.fc44 dans repos officiels F44.
# Pas de COPR ici (grub-btrfs est COPR kylegospo, volontairement exclu pour primée sécu).
RUN <<EORUN
set -xeuo pipefail
dnf -y install bootc ostree selinux-policy-targeted dracut-live plymouth btrfs-progs xfsprogs dosfstools \
  snapper btrfs-assistant libdnf5-plugin-actions inotify-tools htop fastfetch gparted
# Timers Snapper : timeline + cleanup + boot (configs créées au 1er boot, voir note)
systemctl enable snapper-timeline.timer snapper-cleanup.timer snapper-boot.timer || true
# Intégration dnf5 : snapshots pre/post auto pour dnf, GNOME Software, KDE Discover (F44 = backend libdnf5)
mkdir -p /etc/dnf/libdnf5-plugins/actions.d
cat > /etc/dnf/libdnf5-plugins/actions.d/snapper.actions <<'EOF'
# Get snapshot description
pre_transaction::::/usr/bin/sh -c echo\ "tmp.cmd=$(ps\ -o\ command\ --no-headers\ -p\ '${pid}')"
# Pre snapshots root + home avec cleanup number
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_root=$(snapper\ -c\ root\ create\ -c\ number\ -t\ pre\ -p\ -d\ '${tmp.cmd}')"
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_home=$(snapper\ -c\ home\ create\ -c\ number\ -t\ pre\ -p\ -d\ '${tmp.cmd}')"
# Post snapshots si pre existent
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_root}"\ ]\ &&\ snapper\ -c\ root\ create\ -c\ number\ -t\ post\ --pre-number\ "${tmp.snapper_pre_root}"\ -d\ "${tmp.cmd}"
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_home}"\ ]\ &&\ snapper\ -c\ home\ create\ -c\ number\ -t\ post\ --pre-number\ "${tmp.snapper_pre_home}"\ -d\ "${tmp.cmd}"
EOF
chmod 644 /etc/dnf/libdnf5-plugins/actions.d/snapper.actions
# Pas de blacklist nouveau/nova ici : sans pilote proprio installé,
# ce sont eux qui affichent. Le script post-install les ajoutera.
EORUN
# NOTE 1er boot (à faire sur système installé, pas au build) :
#   snapper -c root create-config /
#   snapper -c home create-config /home
# Puis gérer dans Btrfs Assistant (timeline, nettoyage, restore).
# grub-btrfs (boot sur snapshot depuis GRUB) non inclus : COPR uniquement.

# ######################################################################
# D. MULTIMÉDIA — étapes 5 codecs, 6 AppImage/Flatpak
# ######################################################################
# 5. Codecs complets via RPMFusion (Negativo17 abandonné : one-man repo,
# point de défaillance + conflits x265. Fichier repo conservé DÉSACTIVÉ
# en porte de sortie, cf. ci-dessous.)
RUN <<EORUN
set -xeuo pipefail
# config-manager (dnf5-plugins) REQUIS : sans lui les setopt ci-dessous
# échouent en silence (|| true) et les dépôts restent dans l'état précédent.
dnf -y install dnf-plugins-core dnf5-plugins curl
# Negativo17 : repo conservé mais DÉSACTIVÉ (porte de secours).
# Ne JAMAIS l'activer en même temps que RPMFusion (incompatibles).
curl -L -o /etc/yum.repos.d/fedora-multimedia.repo https://negativo17.org/repos/fedora-multimedia.repo || true
dnf config-manager setopt fedora-multimedia.enabled=0
# RPMFusion : la source principale (équipe + miroirs, compatible écosystème)
dnf -y install \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" || true
dnf config-manager setopt rpmfusion-free.enabled=1 rpmfusion-nonfree.enabled=1 \
  rpmfusion-free-updates.enabled=1 rpmfusion-nonfree-updates.enabled=1
# Pour réactiver Negativo17 un jour (porte de secours) :
#   dnf config-manager setopt fedora-multimedia.enabled=1
# + redésactiver RPMFusion. Ne JAMAIS les activer ensemble sans tester en VM.
# OpenH264 Cisco (royalties payées, pour Firefox/WebRTC)
dnf config-manager setopt fedora-cisco-openh264.enabled=1
# Full ffmpeg RPMFusion (complet, remplace ffmpeg-free limité de Fedora)
# Fallback car ffmpeg-free peut être absent avant le groupe GNOME (swap échouerait sinon)
dnf -y swap ffmpeg-free ffmpeg --allowerasing || dnf -y install ffmpeg --allowerasing || true
# Stack GStreamer + FFmpeg + MP3 + VA (liste individuelle, @multimedia incompatible dnf5)
dnf -y install --setopt="install_weak_deps=False" \
  gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free \
  gstreamer1-plugins-bad-freeworld \
  gstreamer1-plugins-ugly \
  gstreamer1-plugins-ugly-free \
  gstreamer1-plugin-openh264 \
  gstreamer1-plugin-libav \
  ffmpeg-libs \
  openh264 mozilla-openh264 \
  lame libva libva-utils \
  --exclude=PackageKit-gstreamer-plugin
dnf clean all
EORUN

# 5b. Nvidia RPMFusion (optionnel, WITH_NVIDIA=1) — baké = rebuildé
# AVEC le kernel de l'image : pas de désync black-screen possible.
# (RPMFusion, pas Negativo : voir doctrine étape 5.)
RUN <<EORUN
set -xeuo pipefail
if [ "${WITH_NVIDIA:-0}" = "1" ]; then
  dnf -y install akmod-nvidia xorg-x11-drv-nvidia nvidia-settings \
    nvidia-persistenced nvidia-modprobe xorg-x11-drv-nvidia-cuda egl-wayland \
    xorg-x11-drv-nvidia-libs.i686 gcc kmodtool akmods
  KVER=$(ls /usr/lib/modules | grep -i cachy | sort -V | tail -1)
  echo "Build akmod-nvidia pour : $KVER"
  akmods --force --kernels "$KVER" --kmod nvidia \
    || (cat /var/cache/akmods/nvidia/*.failed.log; exit 1)
  find "/usr/lib/modules/${KVER}" -name "nvidia.ko*" | grep -q . \
    || { echo "kmod nvidia manquant pour $KVER"; exit 1; }
  systemctl enable nvidia-persistenced || true
  # Blacklist open + kargs (présents seulement si pilote présent)
  echo "blacklist nouveau" > /etc/modprobe.d/blacklist-nouveau.conf
  echo "options nouveau modeset=0" >> /etc/modprobe.d/blacklist-nouveau.conf
  echo "blacklist nova_core" > /etc/modprobe.d/blacklist-novecore.conf
  mkdir -p /usr/lib/bootc/kargs.d
  cat > /usr/lib/bootc/kargs.d/nvidia.toml <<'EOF'
kargs = ["nvidia-drm.modeset=1", "nvidia-drm.fbdev=1"]
match-architectures = ["x86_64"]
EOF
  echo "options nvidia-drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia-drm-modeset.conf
  printf "nvidia\nnvidia_modeset\nnvidia_uvm\nnvidia_drm\n" > /etc/modules-load.d/nvidia.conf
fi
echo "Nvidia: WITH_NVIDIA=${WITH_NVIDIA:-0} (0=sans, 1=baké)"
dnf clean all
rm -rf /var/cache/akmods /tmp/*
bootc container lint
EORUN

# 6. Support AppImage + Flatpak intégré (vérifié F44 bootc)
# F44 Atomic a retiré FUSE2 du base : il faut fuse+fuse-libs (Type-1 anciens) + fuse3 (Type-2 modernes).
# Intégration menu via Gearlever Flatpak (it.mijorus.gearlever), pas appimaged déprécié.
# Bootc : /var perdu au build, donc remote persistant via /etc/flatpak/remotes.d (pas remote-add seul).
RUN <<EORUN
set -xeuo pipefail
dnf -y install fuse fuse-libs fuse3 fuse3-libs squashfs-tools flatpak xdg-desktop-portal
# Flathub persistant image (système) : survit au build, dispo dès 1er boot
mkdir -p /etc/flatpak/remotes.d
curl -L -o /etc/flatpak/remotes.d/flathub.flatpakrepo https://flathub.org/repo/flathub.flatpakrepo
# Pas de `flatpak install` au build : /var non persisté, preinstall non standard.
# Les flatpaks s'installent au 1er boot / via ISO (ex: Gearlever).
dnf clean all
bootc container lint
EORUN
# NOTE 1er boot : flatpak install flathub it.mijorus.gearlever
# Fallback sans FUSE (conteneur/VM restreinte) : ./app.AppImage --appimage-extract-and-run

# ######################################################################
# E. ADDONS CACHYOS — étape 7
# ######################################################################
# 7. CachyOS Addons (vérifié : cache COPR + GitHub CachyOS/copr-linux-cachyos, F44 x86_64 OK)
# Contenu : cachyos-settings, scx-scheds/scX-tools (release, pas -git), scx-manager, ananicy-cpp.
# Sécu : même mainteneur que ton kernel (bieszczaders/CachyOS), versions release uniquement.
RUN <<EORUN
set -xeuo pipefail
curl -L -o /etc/yum.repos.d/bieszczaders-kernel-cachyos-addons-fedora-44.repo \
  https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos-addons/repo/fedora-44/bieszczaders-kernel-cachyos-addons-fedora-44.repo
# Settings CachyOS (modprobe + udev) à la place des defaults Fedora
dnf -y swap zram-generator-defaults cachyos-settings || dnf -y install cachyos-settings
# Schedulers sched-ext + GUI + auto-nice (release, pas git snapshot)
dnf -y install scx-scheds scx-tools scx-manager ananicy-cpp cachyos-ananicy-rules || \
  dnf -y install scx-scheds scx-tools scx-manager ananicy-cpp
systemctl enable ananicy-cpp || true
systemctl enable scx_loader || true
# CachyOS-settings touche modprobe/initramfs : rebuild pour le kernel CachyOS
KVER=$(ls /usr/lib/modules | grep -i cachy | sort -V | tail -1)
dracut --reproducible --no-hostonly --add "ostree" --force "/usr/lib/modules/${KVER}/initramfs.img" "${KVER}" || true
rm -rf /boot/*
dnf clean all
EORUN

# ######################################################################
# F. GAMING — étape 8 stack (réglages étape 12)
# ######################################################################
# 8. Gaming : stack VOLONTAIREMENT hors image (poids ~2 Go).
# Post-install : WITH_GAMING=1 ./install-flatpaks.sh (Flatpak, persistant).
# Seul steam-devices (règles udev manettes, Ko) reste baké.
RUN <<EORUN
set -xeuo pipefail
dnf -y install steam-devices || true
dnf clean all
bootc container lint
EORUN
# NOTE 1er boot gaming (Flatpak, pas de COPR) :
#   flatpak install flathub com.heroicgameslauncher.hgl net.davidotek.pupgui2
# ProtonUp-Qt gère GE-Proton pour Steam/Lutris/Heroic. Heroic embarque son runtime.
# Oubliés dans ta liste, ajoutés : gamemode, gamescope, goverlay, vkBasalt,
#   steam-devices (udev manettes), nvidia-driver-libs.i686 (jeux 32-bit), libva-nvidia-driver.

# ######################################################################
# G. BUREAU GNOME — étapes 9 gestion, 10 bureau
# ######################################################################
# 9. Gestion GNOME complète : Ajustements + Extensions + Bazaar
# Vérifié : gnome-tweaks-49.0-2.fc44 officiel, Extension Manager + Bazaar en Flatpak Flathub.
# En F44/GNOME 50 les extensions ne sont plus dans Tweaks, il faut gnome-extensions-app + Extension Manager.
RUN <<EORUN
set -xeuo pipefail
dnf -y install gnome-tweaks gnome-extensions-app gnome-browser-connector || \
  dnf -y install gnome-tweaks gnome-extensions-app || true
dnf clean all
EORUN
# NOTE 1er boot gestion (Flatpak, preinstall impossible en bootc car /var non persisté) :
#   flatpak install flathub io.github.kolunmi.Bazaar com.mattjakeman.ExtensionManager it.mijorus.gearlever
# Bazaar = magasin Flatpak/Flathub, Extension Manager = browse/install extensions GNOME,
# Ajustements (gnome-tweaks) = polices, thèmes GTK, boutons fenêtres, démarrage.

# 10. Bureau GNOME officiel façon Fedora Workstation (GNOME 50, Wayland)
# Réf vérifiée : méthode bootc Fedora Magazine (@kde-desktop-environment -> équivalent GNOME).
# Base bootc minimale + groupe GNOME + gdm graphique, comme l'ISO officielle.
RUN <<EORUN
set -xeuo pipefail
# Produit Workstation (branding, repos) + bureau GNOME complet
dnf -y install fedora-release-workstation || true
dnf -y group install "GNOME Desktop Environment" --setopt="install_weak_deps=False" || \
  dnf -y install @gnome-desktop || \
  dnf -y install gnome-shell gdm gnome-control-center gnome-terminal nautilus \
    gnome-software gnome-text-editor gnome-calculator gnome-system-monitor \
    evince eog firefox yelp gnome-backgrounds gnome-fonts || true
# Day-2 bootc : /opt déjà lié vers /var/opt à l'étape 1, on s'assure juste du dossier
mkdir -p /var/opt
# Boot graphique + login manager comme Workstation officielle
systemctl enable gdm || true
systemctl set-default graphical.target || true
dnf clean all
EORUN

# ######################################################################
# H. OPTIMISATIONS — étape 11 hardware
# ######################################################################
# 11. Optimisation 1/2 — Hardware i9-14900K + 32GB DDR5 + 2x NVMe + RTX 4070
# Choix validés : mitigations ON, tuned-ppd gardé. Sécu primée.
RUN <<EORUN
set -xeuo pipefail
# Microcode Intel critique 14900K + thermique + énergie desktop
dnf -y install microcode_ctl thermald tuned tuned-ppd fwupd smartmontools lm_sensors || \
  dnf -y install microcode_ctl thermald tuned fwupd || true
# Conflit avéré : tuned-ppd et power-profiles-daemon se battent (choix validé = tuned-ppd)
dnf -y remove power-profiles-daemon || true
systemctl enable thermald || true
# tuned-ppd déjà défaut F44, on ne bascule PAS sur power-profiles-daemon (choix validé)
# iGPU UHD 770 en offload QuickSync (Nvidia reste principale pour le rendu).
# intel-media-driver est dans Fedora officiel : pas de RPMFusion ici
# (doctrine étape 5 : Negativo17 seul, RPMFusion désactivé).
dnf -y install intel-media-driver || \
  echo "pas de intel-media-driver, NVDEC Nvidia couvre le décodage"
# NVMe : trim hebdo + scheduler none (meilleur latence NVMe que mq-deadline/bfq)
systemctl enable fstrim.timer || true
# Point de montage 2e disque polyvalent (fstab par UUID au 1er boot via script embarqué)
# /mnt est un lien ostree vers /var/mnt vide au build : créer la cible réelle d'abord
mkdir -p /var/mnt /mnt/data
cat > /etc/udev/rules.d/60-nvme-scheduler.rules <<'EOF'
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
EOF
# 32GB DDR5 : on garde zram cachyos-settings, pas de swap disque ajouté ici
dnf clean all
EORUN
# NOTE 2e NVMe (jeux) : à monter après install, ex /mnt/jeux en noatime,
# puis pointer Steam dessus. Pas formaté dans l'image par sécu.
# Script embarqué : sudo setup-second-disk.sh (écrit la fstab par UUID, plus de mot de passe après).
# /usr/bin car /usr/local est un lien vers /var non persisté en bootc.
COPY host-scripts/setup-second-disk.sh /usr/bin/setup-second-disk.sh
RUN chmod 755 /usr/bin/setup-second-disk.sh

# ######################################################################
# F. GAMING (suite) — étape 12 réglages
# ######################################################################
# 12. Optimisation 2/2 — Gaming (complète le stack étape 8, mitigations ON)
RUN <<EORUN
set -xeuo pipefail
# scx_lavd Gaming par défaut, irqbalance coupé (conflit avéré = micro-saccades)
mkdir -p /etc/scx_loader
cat > /etc/scx_loader/config.toml <<'EOF'
default_sched = "scx_lavd"
default_mode = "Gaming"
[scheds.scx_lavd]
auto_mode = ["--performance"]
gaming_mode = ["-m", "performance"]
EOF
systemctl disable irqbalance || true
systemctl mask irqbalance || true
# scx_loader déjà activé étape 7, config ci-dessus prise au prochain boot
# GameMode Nvidia 615 : renice + ioprio + optims GPU
cat > /etc/gamemode.ini <<'EOF'
[general]
renice=10
ioprio=1
[gpu]
apply_gpu_optimisations=accept-responsibility
gpu_device=0
EOF
# Proton/wine : valeur officielle Fedora (déjà défaut F44, posée explicite)
cat > /etc/sysctl.d/99-gaming.conf <<'EOF'
vm.max_map_count=1048576
EOF
# Nvidia Wayland : seulement si pilote baké (WITH_NVIDIA=1),
# sinon fichiers inertes voire bruyants au boot. Voir étape 5b.
if [ "${WITH_NVIDIA:-0}" = "1" ]; then
  mkdir -p /usr/lib/bootc/kargs.d
  cat > /usr/lib/bootc/kargs.d/nvidia.toml <<'EOF'
kargs = ["nvidia-drm.modeset=1", "nvidia-drm.fbdev=1"]
match-architectures = ["x86_64"]
EOF
  echo "options nvidia-drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia-drm-modeset.conf
  echo "options nvidia NVreg_PreserveVideoMemoryAllocations=1" > /etc/modprobe.d/nvidia-pm.conf
  printf "nvidia\nnvidia_modeset\nnvidia_uvm\nnvidia_drm\n" > /etc/modules-load.d/nvidia.conf
fi
# Mitigations volontairement ON (choix sécu), aucun mitigations=off ici
dnf clean all
bootc container lint
EORUN
# NOTE Steam : options de lancement conseillées par jeu : gamemoderun mangohud %command%

# ######################################################################
# H. OPTIMISATIONS (suite) — étape 13 divers
# ######################################################################
# 13. Autres optimisations validées : btrfs, oomd, WiFi latence, boot, VM test
# Vérifié : btrfsmaintenance-0.5.2-6.fc44 officiel F44.
RUN <<EORUN
set -xeuo pipefail
# Btrfs scrub mensuel + balance (trim déjà via fstrim.timer étape 11, pas de doublon)
dnf -y install btrfsmaintenance || true
systemctl enable btrfs-scrub.timer btrfs-balance.timer || true
# OOM propre en cas de fuite VRAM/Proton au lieu d'un freeze (32GB)
systemctl enable systemd-oomd || true
# WiFi MT7927 latence gaming : coupe le powersave qui aggrave les retransmissions EHT
mkdir -p /etc/NetworkManager/conf.d
printf "[connection]\nwifi.powersave=2\n" > /etc/NetworkManager/conf.d/wifi-powersave.conf
# Boot GDM plus rapide + firmwares à jour
systemctl mask NetworkManager-wait-online.service || true
systemctl enable fwupd-refresh.timer || true
# VM test ISO bootc en snapshot (zéro risque hardware vs bare metal)
dnf -y install libvirt qemu-kvm virt-manager virt-viewer || true
systemctl enable libvirtd || true
dnf clean all
bootc container lint
EORUN
# NOTE 1er boot : sudo usermod -aG libvirt $USER (puis relog), VM GNOME Boxes/virt-manager pour tester les ISO.

# ######################################################################
# G. BUREAU (suite) — étape 14 réglages GNOME
# ######################################################################
# 14. Optimisations GNOME 50 Wayland (RTX 4070, NVMe)
# XWayland conservé pour vieux jeux Proton. Tracker indexe $HOME par défaut,
# /mnt/data déjà exclu : on le rappelle en note, pas de paquet à retirer.
RUN <<EORUN
set -xeuo pipefail
dnf -y install xorg-x11-server-Xwayland dconf || true
# Extensions système (vérif web indisponible, quota atteint : install tentée, fallback gracieux, log de build fera foi)
dnf -y install gnome-shell-extension-appindicator gnome-shell-extension-vitals || \
  dnf -y install gnome-shell-extension-appindicator || \
  echo "extensions RPM absentes, passer par Extension Manager au 1er boot"
# 1. Tracker : défaut système = XDG home uniquement, /mnt/data (jeux/ISO) jamais indexé
mkdir -p /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/00-tracker <<'EOF'
[org/freedesktop/Tracker3/Miner/Files]
index-recursive-directories=['&DESKTOP', '&DOCUMENTS', '&DOWNLOAD', '&MUSIC', '&PICTURES', '&VIDEOS']
index-single-directories=[]
EOF
dconf update || true
dnf clean all
bootc container lint
EORUN
# 2. Extensions : RPM ci-dessus si dispo, sinon Extension Manager (liées à la version Shell).
# 3. Énergie : Performance sur secteur via Paramètres → Énergie (tuned-ppd gardé, pas de TLP).
#    Volontairement pas forcé dans l'image : dépend secteur/batterie.
# 5. 4K uniquement : gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']".
#    Volontairement pas forcé : mauvais sur écran non-4K.
# NOTE GNOME 1er boot :
# - Recherche : vérifier que /mnt/data est exclu (Paramètres → Recherche), Tracker sinon gratte les NVMe en jeu.
# - Énergie : profil Performance sur secteur (intégré tuned-ppd gardé).
# - Extensions via Extension Manager : Vitals (temps 14900K/4070) + AppIndicator (Steam/Discord/Lutris).
# - 4K uniquement : gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']".

# ######################################################################
# H. OPTIMISATIONS (suite) — étapes 15 audio/réseau/sécu, 16 finitions, 17 final
# ######################################################################
# 15. Oubliés critiques : audio, réseau, pare-feu, updates auto
RUN <<EORUN
set -xeuo pipefail
# Audio PipeWire (sautés par le groupe GNOME en weak_deps=False)
dnf -y install pipewire wireplumber pipewire-alsa || true
dnf -y install pipewire-pulseaudio || dnf -y install pipewire-pulse || true
# Réseau WiFi/BT explicite (le conf NetworkManager seul ne suffit pas)
dnf -y install NetworkManager NetworkManager-wifi wpa_supplicant bluez || true
systemctl enable NetworkManager bluetooth || true
# Pare-feu + GUI + applet + fail2ban (sécu primée)
dnf -y install firewalld firewall-config firewall-applet fail2ban || \
  dnf -y install firewalld fail2ban || true
systemctl enable firewalld fail2ban || true
# Updates bootc : MANUELLES, pas d'auto-apply.
# Motif : avec pilote Nvidia post-install, une update auto + nouveau
# kernel = kmod absent + nouveau blacklisté = écran noir programmé.
# Vérifier via update-gui.py ou `bootc upgrade --check`, appliquer,
# rebooter, puis relancer install-nvidia-host.sh.
systemctl disable bootc-fetch-apply-updates.timer || true
systemctl mask bootc-fetch-apply-updates.timer || true
dnf clean all
bootc container lint
EORUN

# 16. Restes du check : portails partage écran, codecs casque BT, horloge
RUN <<EORUN
set -xeuo pipefail
# Backends portails Wayland (Discord/Steam screen share)
dnf -y install xdg-desktop-portal-gnome xdg-desktop-portal-gtk || true
# Codecs casque BT aptX/LDAC (RPMFusion, source principale désormais)
# Excludes : ne jamais laisser RPMFusion toucher au kernel/CachyOS,
# géré par les dépôts Fedora/COPR dédiés.
dnf -y install libfreeaptx libldac fdk-aac || \
  dnf -y install --enablerepo=rpmfusion-free --exclude='ffmpeg*' --exclude='gstreamer*' --exclude='*nvidia*' libfreeaptx libldac fdk-aac || \
  echo "codecs BT absents, casques en SBC de base"
# Horloge (TLS/Steam/GNOME)
dnf -y install chrony || true
systemctl enable chronyd || true
dnf clean all
EORUN

# 17. Final : IOMMU libvirt + rebuild initramfs (microcode/firmwares post-étape 7)
RUN <<EORUN
set -xeuo pipefail
cat > /usr/lib/bootc/kargs.d/intel.toml <<'EOF'
kargs = ["intel_iommu=on", "iommu=pt"]
match-architectures = ["x86_64"]
EOF
KVER=$(ls /usr/lib/modules | grep -i cachy | sort -V | tail -1)
# Ceinture : le module dracut clevis doit exister (requis par la conf, sinon dracut meurt)
dnf -y install clevis-dracut || true
dracut --reproducible --no-hostonly --add "ostree" --force "/usr/lib/modules/${KVER}/initramfs.img" "${KVER}"
rm -rf /boot/*
dnf clean all
bootc container lint
EORUN

# ######################################################################
# I. OUTILS & TERMINAL — étapes 18 parité, 19 zsh, 20 omz/p10k
# ######################################################################
# 18. Parité Bazzite/CachyOS : distrobox, impression, vulkan-tools, polices jeux
RUN <<EORUN
set -xeuo pipefail
dnf -y install distrobox cups vulkan-tools ttf-liberation || \
  dnf -y install distrobox cups vulkan-tools || true
systemctl enable cups || true
# HP : baké seulement si WITH_PRINTER=1 (poids + Qt),
# sinon install-hplip-host.sh post-install.
if [ "${WITH_PRINTER:-0}" = "1" ]; then
  dnf -y install hplip hplip-gui || dnf -y install hplip || true
fi
echo "Printer: WITH_PRINTER=${WITH_PRINTER:-0} (0=script post-install, 1=baké)"
dnf clean all
bootc container lint
EORUN

# 19. Zsh complet (vérifié dnf : zsh-5.9, autosuggestions-0.7.1, syntax-highlighting-0.8.0 F44 officiels)
RUN <<EORUN
set -xeuo pipefail
dnf -y install zsh zsh-autosuggestions zsh-syntax-highlighting
# Shell par défaut des nouveaux users (créés à l'install Anaconda)
grep -q "^SHELL=" /etc/default/useradd && sed -i "s|^SHELL=.*|SHELL=/bin/zsh|" /etc/default/useradd || echo "SHELL=/bin/zsh" >> /etc/default/useradd
# NOTE : le .zshrc skel est écrit à l'étape 20 (omz/p10k), pas ici.
dnf clean all
bootc container lint
EORUN
# NOTE 1er boot user existant : chsh -s /bin/zsh (puis relog).

# 20. Zsh plugins + thème powerlevel10k (pinnés, vérifiés le 15/09/2026)
# omz sans tag upstream -> pinné commit fcf9659, p10k tag v1.9.1, fonts RPM.
RUN <<EORUN
set -xeuo pipefail
dnf -y install git powerline-fonts
OMZ_HASH="fcf965912c4adf73ead540e7409bb42ec6e31b45"
rm -rf /etc/skel/.oh-my-zsh
git init -q /etc/skel/.oh-my-zsh
git -C /etc/skel/.oh-my-zsh remote add origin https://github.com/ohmyzsh/ohmyzsh.git
git -C /etc/skel/.oh-my-zsh fetch -q --depth 1 origin "$OMZ_HASH"
git -C /etc/skel/.oh-my-zsh checkout -q FETCH_HEAD
git clone -q --depth 1 --branch v1.9.1 https://github.com/romkatv/powerlevel10k.git /etc/skel/.oh-my-zsh/custom/themes/powerlevel10k
cat > /etc/skel/.zshrc <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
zstyle ':omz:update' mode disabled
plugins=(git sudo dnf colored-man-pages command-not-found)
source $ZSH/oh-my-zsh.sh
HISTFILE=~/.zsh_history
HISTSIZE=5000
SAVEHIST=5000
setopt APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS
[[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
EOF
chmod 644 /etc/skel/.zshrc
dnf clean all
bootc container lint
EORUN
# NOTE 1er boot : p10k configure (assistant thème, choisir une Powerline font dans GNOME Terminal).
