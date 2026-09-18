#!/usr/bin/env python3
# update-gui.py — petite GUI GTK4 pour les mises à jour bootc + flatpak.
# Usage : python3 update-gui.py
# (pkexec demande le mot de passe pour les actions privilégiées)
"""Petit panneau de mise à jour pour système bootc.

- Affiche `bootc status` et `flatpak update` (simulation).
- Boutons : vérifier, appliquer (bootc upgrade), rollback, reboot.
- Les commandes longues tournent en thread, log dans la fenêtre.
"""

import subprocess
import threading
import sys

try:
    import gi
    gi.require_version("Gtk", "4.0")
    from gi.repository import Gtk, GLib
except (ImportError, ValueError) as exc:
    print(f"GTK4/PyGObject manquant ({exc}). Installe : python3-gobject gtk4")
    sys.exit(1)


def run(cmd):
    """Exécute une commande, retourne (code, sortie)."""
    proc = subprocess.run(cmd, capture_output=True, text=True)
    out = (proc.stdout or "") + (proc.stderr or "")
    return proc.returncode, out.strip()


class UpdateWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Mises à jour bootc")
        self.set_default_size(640, 480)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)
        self.set_child(box)

        # Barre de boutons
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        box.append(bar)
        for label, cmd in [
            ("Statut", None),
            ("Vérifier", ["pkexec", "bootc", "upgrade", "--check"]),
            ("Appliquer", ["pkexec", "bootc", "upgrade"]),
            ("Rollback", ["pkexec", "bootc", "rollback"]),
            ("Flatpak", ["flatpak", "update", "-y"]),
            ("Reboot", ["pkexec", "reboot"]),
        ]:
            btn = Gtk.Button(label=label)
            btn.connect("clicked", self.on_button, cmd)
            bar.append(btn)

        # Zone de log
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        box.append(scroll)
        self.logview = Gtk.TextView(editable=False, monospace=True)
        scroll.set_child(self.logview)
        self.log("Prêt. 'Statut' pour commencer.\n")

    def log(self, text):
        buf = self.logview.get_buffer()
        buf.insert(buf.get_end_iter(), text + "\n")

    def on_button(self, _btn, cmd):
        if cmd is None:
            self.refresh_status()
            return
        self.log(f"$ {' '.join(cmd)}")
        threading.Thread(target=self._run_bg, args=(cmd,), daemon=True).start()

    def _run_bg(self, cmd):
        code, out = run(cmd)
        GLib.idle_add(self.log, f"[sortie {code}]\n{out}\n")
        if cmd[:3] == ["pkexec", "bootc", "upgrade"]:
            GLib.idle_add(self.log, "Reboote pour appliquer (bouton Reboot).")

    def refresh_status(self):
        self.log("$ bootc status")
        threading.Thread(target=self._status_bg, daemon=True).start()

    def _status_bg(self):
        code, out = run(["bootc", "status"])
        GLib.idle_add(self.log, f"[sortie {code}]\n{out}\n")


class UpdateApp(Gtk.Application):
    def do_activate(self):
        win = UpdateWindow(self)
        win.present()


if __name__ == "__main__":
    UpdateApp().run(None)
