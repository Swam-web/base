#!/usr/bin/env bash
# install-hplip-host.sh — pilotes HP (impression + scan), POST-INSTALL.
# Utile si l'image ne les embarque pas. Inutile si déjà bakés.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Relance avec sudo."
  exit 1
fi

# bootc : /usr est en lecture seule -> overlay inscriptible POUR CE BOOT.
# (Transitoire : à refaire après chaque `bootc upgrade`.)
if command -v bootc >/dev/null 2>&1; then
  echo "==> bootc détecté : usr-overlay..."
  bootc usr-overlay
fi

if rpm -q hplip >/dev/null 2>&1; then
  echo "hplip déjà installé, rien à faire."
else
  echo "==> Installation hplip + gui..."
  dnf -y install hplip hplip-gui || dnf -y install hplip
fi

echo "==> CUPS actif ?"
systemctl enable --now cups || true

cat <<'EOF'

OK. Suite :
  - Imprimante USB : branche-la, puis `hp-setup` (ou GNOME Paramètres).
  - Réseau : détection auto via CUPS/Avahi, sinon `hp-setup` + IP.
  - Scan : backend hpaio (`hp-scan --help` pour tester).
  - Vérif : `hp-check -r`
Rappel bootc : overlay transitoire — après un `bootc upgrade`,
relance ce script (ou bake dans l'image).
EOF
