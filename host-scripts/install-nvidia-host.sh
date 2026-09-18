#!/usr/bin/env bash
# install-nvidia-host.sh — pilote Nvidia RPMFusion, POST-INSTALL sur host.
# (Negativo17 abandonné : one-man repo. Fichier repo conservé désactivé
# dans l'image en porte de secours, non utilisé ici.)
# À lancer UNIQUEMENT sur la vraie machine (RTX), jamais en VM.
# akmods compile contre le kernel QUI TOURNE => pas de désync black-screen.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Relance avec sudo."
  exit 1
fi

lspci | grep -qi nvidia || { echo "Pas de GPU Nvidia détecté. Abandon."; exit 1; }

# bootc : /usr est en lecture seule -> overlay inscriptible POUR CE BOOT.
# (Transitoire : à refaire après chaque `bootc upgrade`.)
if command -v bootc >/dev/null 2>&1; then
  echo "==> bootc détecté : usr-overlay..."
  bootc usr-overlay
fi

KVER="$(uname -r)"
echo "==> Kernel actif : $KVER"

echo "==> Repos RPMFusion ( Negativo17 reste désactivé )..."
dnf -y install dnf-plugins-core dnf5-plugins curl
dnf -y install \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" || true

echo "==> Nettoyage résidus Nvidia..."
dnf -y remove '*nvidia*' || true

echo "==> Installation driver + akmod (RPMFusion)..."
dnf -y install akmod-nvidia xorg-x11-drv-nvidia nvidia-settings \
  nvidia-persistenced nvidia-modprobe xorg-x11-drv-nvidia-cuda egl-wayland \
  kernel-cachyos-devel-matched gcc kmodtool akmods
# 32-bit (jeux/wine) + VAAPI, optionnels (libva-nvidia-driver = Negativo
# uniquement : ignoré en silence si absent, Firefox/MPV s'en passent)
dnf -y install xorg-x11-drv-nvidia-libs.i686 libva-nvidia-driver || true

echo "==> Build kmod pour $KVER..."
akmods --force --kernels "$KVER" --kmod nvidia \
  || (cat /var/cache/akmods/nvidia/*.failed.log; exit 1)
ls "/usr/lib/modules/${KVER}/extra/nvidia" 2>/dev/null || \
  find "/usr/lib/modules/${KVER}" -name "nvidia.ko*" | grep -q . \
  || { echo "kmod nvidia manquant pour $KVER"; exit 1; }

echo "==> Blacklist nouveau/nova + services..."
echo "blacklist nouveau" > /etc/modprobe.d/blacklist-nouveau.conf
echo "options nouveau modeset=0" >> /etc/modprobe.d/blacklist-nouveau.conf
echo "blacklist nova_core" > /etc/modprobe.d/blacklist-novecore.conf
systemctl enable nvidia-persistenced || true
# Anti-périple : akmods rebuild le kmod TOUT SEUL à chaque nouveau kernel
# (au boot suivant, avant GDM). Ne plus jamais y penser.
# Requiert kernel-cachyos-devel-matched présent (installé ci-dessus).
systemctl enable akmods || true

cat <<'EOF'

OK. Prochaines étapes :
  1. Secure Boot : kmods non signés clé Fedora => désactivez-le
     ou enrolez votre clé MOK, sinon écran noir.
  2. Reboot, puis vérifiez : nvidia-smi
  3. Rappel bootc : l'overlay est transitoire. Après un
     `bootc upgrade`, relancez ce script.
EOF
