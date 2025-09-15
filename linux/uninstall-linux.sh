#!/usr/bin/env bash
# uninstall-linux.sh — Remove SKY130 PDK, launchers, and (optionally) our no-GL Magic
set -euo pipefail

REMOVE_MAGIC=0
for a in "$@"; do [ "$a" = "--remove-magic" ] && REMOVE_MAGIC=1; done

WORKDIR="$HOME/.eda-bootstrap"
MANIFEST="$WORKDIR/install-manifest.txt"

say(){ printf '%s\n' "$*"; }
rm_path(){
  local kind="$1" path="$2"
  if [ "$kind" = FILE ] && [ -e "$path" ]; then sudo rm -f "$path" || true; fi
  if [ "$kind" = DIR ]  && [ -d "$path" ]; then sudo rm -rf "$path" || true; fi
}

if [ -f "$MANIFEST" ]; then
  say "Using manifest: $MANIFEST"
  while read -r kind path; do rm_path "$kind" "$path"; done < "$MANIFEST"
else
  say "Manifest not found; using safe heuristics…"
  for f in "$HOME/.local/bin/magic-sky130" "$HOME/.local/bin/magic-sky130-xsafe" "$HOME/.local/bin/magic-sky130-nogl"; do sudo rm -f "$f" 2>/dev/null || true; done
  for d in /opt/pdk/sky130A /opt/pdk/sky130B "$HOME/.config/sky130" "$HOME/sky130-demo" "$HOME/.eda-bootstrap"; do sudo rm -rf "$d" 2>/dev/null || true; done
fi

# Optionally remove Magic only if our nogl marker exists (to avoid nuking a system install)
if [ "$REMOVE_MAGIC" -eq 1 ]; then
  if [ -f /usr/local/share/magic/.sky130_nogl_marker ]; then
    say "Removing no-GL Magic we installed…"
    sudo rm -f /usr/local/bin/magic || true
    sudo rm -rf /usr/local/share/magic || true
  else
    say "No marker found; refusing to remove /usr/local Magic (could be system-provided)."
  fi
fi

say "Uninstall complete."
