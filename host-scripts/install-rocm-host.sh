#!/usr/bin/env bash
# install-rocm-host.sh — userspace AMD ROCm, POST-INSTALL sur machine bootc.
# Pas de kmod (amdgpu in-kernel) : aucun risque de désync, mais /usr étant
# verrouillé sur bootc, passage par usr-overlay (transitoire).
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Relance avec sudo."
  exit 1
fi

lspci | grep -qi -E "amd|advanced micro" || { echo "Pas de GPU AMD détecté. Abandon."; exit 1; }
lsmod | grep -q amdgpu || echo "NOTE : module amdgpu non chargé (vérifie le boot)."

if command -v bootc >/dev/null 2>&1; then
  echo "==> bootc détecté : usr-overlay..."
  bootc usr-overlay
fi

echo "==> Installation ROCm (dépôts Fedora)..."
dnf -y install rocminfo rocm-runtime rocm-hip-runtime rocm-opencl-runtime \
  || dnf -y install rocminfo rocm-runtime \
  || { echo "ROCm indisponible dans les repos actifs"; exit 1; }

command -v rocminfo >/dev/null || { echo "rocminfo introuvable après install"; exit 1; }

cat <<'EOF'

OK. Vérifie avec : rocminfo
Rappel bootc : overlay transitoire — après un `bootc upgrade`,
relance ce script. Pour du permanent, baker dans l'image.
EOF
