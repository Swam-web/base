#!/usr/bin/env bash
# install-flatpaks.sh — installe tous les Flatpak utiles du projet (1er boot).
# Usage sur système installé : sudo ./install-flatpaks.sh
set -euo pipefail

APPS=(
  io.github.kolunmi.Bazaar
  com.mattjakeman.ExtensionManager
  it.mijorus.gearlever
  com.heroicgameslauncher.hgl
  net.davidotek.pupgui2
)

# Gaming (ex-stack natif étape 8, déplacé ici pour maigrir l'image)
GAMING=(
  com.valvesoftware.Steam
  net.lutris.Lutris
  io.github.benjamimgois.goverlay
  org.freedesktop.Platform.VulkanLayer.MangoHud
  org.freedesktop.Platform.VulkanLayer.vkBasalt
)

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub "${APPS[@]}"
echo "OK : ${#APPS[@]} flatpaks installés."
if [ "${WITH_GAMING:-0}" = "1" ]; then
  flatpak install -y flathub "${GAMING[@]}"
  echo "OK : ${#GAMING[@]} flatpaks gaming installés."
else
  echo "Gaming ignoré (WITH_GAMING=1 pour l'ajouter)."
fi
flatpak list --app | grep -E "Bazaar|ExtensionManager|gearlever|heroic|pupgui2|Steam|Lutris" || true
