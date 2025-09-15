#!/usr/bin/env bash
# sky130-linux.sh — Ubuntu/WSL bootstrap for Magic + SKY130 PDK with robust fallbacks + manifest
set -euo pipefail

say(){ printf '%s\n' "$*"; }
ok(){ printf 'OK: %s\n' "$*"; }
warn(){ printf 'WARN: %s\n' "$*"; }
err(){ printf 'ERROR: %s\n' "$*"; }

WORKDIR="$HOME/.eda-bootstrap"
LOGDIR="$WORKDIR/logs"
RC_DIR="$HOME/.config/sky130"
DEMO_DIR="$HOME/sky130-demo"
PDK_PREFIX="/opt/pdk"
MAGIC_VER="${MAGIC_VER:-8.3.551}"
MAGIC_URL="https://github.com/RTimothyEdwards/magic/archive/refs/tags/${MAGIC_VER}.tar.gz"
MANIFEST="$WORKDIR/install-manifest.txt"

mkdir -p "$WORKDIR" "$LOGDIR" "$RC_DIR" "$DEMO_DIR"
: > "$MANIFEST"

step(){ echo; echo "==> $*"; }
record(){ printf '%s %s\n' "$1" "$2" >> "$MANIFEST"; }

step "Updating apt and installing prerequisites…"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential git curl wget pkg-config \
  tcl tcl-dev tk tk-dev \
  libx11-dev libxext-dev libxrender-dev libxft-dev libxpm-dev \
  libcairo2-dev zlib1g-dev libglu1-mesa-dev libgl1-mesa-dev \
  ngspice netgen ca-certificates

# DISPLAY helper (Win10 + external X server)
if [ -z "${DISPLAY:-}" ] && [ -f /etc/resolv.conf ]; then
  export DISPLAY="$(awk '/nameserver /{print $2; exit}' /etc/resolv.conf 2>/dev/null):0"
fi

step "Building Magic ($MAGIC_VER) from source (OpenGL enabled)…"
cd "$WORKDIR"
rm -rf "magic-$MAGIC_VER" magic.tar.gz
curl -fL "$MAGIC_URL" -o magic.tar.gz
tar xf magic.tar.gz
cd "magic-$MAGIC_VER"
./configure --prefix=/usr/local --with-x --with-opengl > "$LOGDIR/magic_configure.log" 2>&1 || true
make -j"$(nproc)" > "$LOGDIR/magic_build.log" 2>&1 || true
sudo make install >> "$LOGDIR/magic_build.log" 2>&1 || true
command -v magic >/dev/null && ok "Magic installed at $(command -v magic)" || warn "Magic (OpenGL) not detected; will try no-GL fallback later."

step "Installing open_pdks + SKY130 into $PDK_PREFIX…"
sudo mkdir -p "$PDK_PREFIX"; sudo chown "$USER":"$USER" "$PDK_PREFIX"
cd "$WORKDIR"
if [ -d open_pdks/.git ]; then (cd open_pdks && git pull --rebase >/dev/null 2>&1) || true; else git clone https://github.com/RTimothyEdwards/open_pdks.git >/dev/null 2>&1 || true; fi
cd open_pdks
./configure --prefix="$PDK_PREFIX" --enable-sky130-pdk --with-sky130-local-path="$PDK_PREFIX" --enable-sram-sky130 > "$LOGDIR/open_pdks_configure.log" 2>&1 || true
make -j"$(nproc)" > "$LOGDIR/open_pdks_build.log" 2>&1 || true
sudo make install >> "$LOGDIR/open_pdks_build.log" 2>&1 || true

choose_pdk(){ for b in "$PDK_PREFIX" "$PDK_PREFIX/share/pdk" /usr/local/share/pdk; do for n in sky130A sky130B; do [ -f "$b/$n/libs.tech/magic/${n}.magicrc" ] && { echo "$b $n"; return 0; }; done; done; return 1; }
if ! read -r PBASE PNAME < <(choose_pdk); then err "SKY130 PDK not detected"; exit 1; fi
ok "PDK found: $PBASE/$PNAME"
record DIR "$PBASE/$PNAME"

step "Writing rc wrapper and demo…"
cat > "$RC_DIR/rc_wrapper.tcl" <<'EOF'
if {![info exists env(PDK_ROOT)]} { set env(PDK_ROOT) "/opt/pdk" }
if {![info exists env(PDK)]} { set env(PDK) "sky130A" }
source "$env(PDK_ROOT)/$env(PDK)/libs.tech/magic/${env(PDK)}.magicrc"
EOF
record FILE "$RC_DIR/rc_wrapper.tcl"

cat > "$DEMO_DIR/inverter_tt.spice" <<'EOF'
.option nomod
.option scale=1e-6
.lib $PDK_ROOT/${PDK}/libs.tech/ngspice/sky130.lib.spice tt
VDD vdd 0 1.8
VIN in 0 PULSE(0 1.8 0n 100p 100p 5n 10n)
CL  out 0 10f
M1  out in 0   0   sky130_fd_pr__nfet_01v8 W=1.0 L=0.15
M2  out in vdd vdd sky130_fd_pr__pfet_01v8 W=2.0 L=0.15
.control
tran 0.1n 50n
plot v(in) v(out)
.endc
.end
EOF
record DIR "$DEMO_DIR"

step "Installing launchers (~/.local/bin)…"
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/magic-sky130" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
choose_pdk(){ for b in /opt/pdk /opt/pdk/share/pdk /usr/local/share/pdk; do for n in sky130A sky130B; do [ -d "$b/$n" ] && { echo "$b $n"; return; }; done; done; }
read -r PBASE PNAME < <(choose_pdk)
export PDK_ROOT="$PBASE" PDK="$PNAME"
[ -n "${DISPLAY:-}" ] || DISPLAY="$(awk '/nameserver /{print $2; exit}' /etc/resolv.conf 2>/dev/null):0"
export DISPLAY
exec magic -norcfile -d X11 -T "$PNAME" -rcfile "$HOME/.config/sky130/rc_wrapper.tcl" "$@"
EOF
chmod +x "$HOME/.local/bin/magic-sky130"
record FILE "$HOME/.local/bin/magic-sky130"

cat > "$HOME/.local/bin/magic-sky130-xsafe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
exec magic-sky130 "$@"
EOF
chmod +x "$HOME/.local/bin/magic-sky130-xsafe"
record FILE "$HOME/.local/bin/magic-sky130-xsafe"

# Probe Magic GUI; if it fails, build no-GL Magic and add nogl launcher
step "Probing Magic GUI…"
GUI_OK=0
( timeout 4s magic -norcfile -d X11 -T "$PNAME" -rcfile "$HOME/.config/sky130/rc_wrapper.tcl" -noc <<<'after 300 { exit 0 } vwait forever' ) >/dev/null 2>&1 && GUI_OK=1 || true

if [ "$GUI_OK" -ne 1 ]; then
  warn "Magic X11 probe failed; building OpenGL-free Magic…"
  cd "$WORKDIR/magic-$MAGIC_VER"
  make distclean >/dev/null 2>&1 || true
  ./configure --prefix=/usr/local --with-x --without-opengl --disable-opengl > "$LOGDIR/magic_nogl_configure.log" 2>&1 || true
  make -j"$(nproc)" > "$LOGDIR/magic_nogl_build.log" 2>&1 || true
  sudo make install >> "$LOGDIR/magic_nogl_build.log" 2>&1 || true
  # marker so our uninstaller only removes magic if we installed the nogl build
  sudo mkdir -p /usr/local/share/magic
  echo "magic-nogl $MAGIC_VER" | sudo tee /usr/local/share/magic/.sky130_nogl_marker >/dev/null
  record FILE "/usr/local/share/magic/.sky130_nogl_marker"
  cat > "$HOME/.local/bin/magic-sky130-nogl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe TK_NO_APPINIT=1
exec magic-sky130 "$@"
EOF
  chmod +x "$HOME/.local/bin/magic-sky130-nogl"
  record FILE "$HOME/.local/bin/magic-sky130-nogl"
  ok "Installed no-GL Magic; use: magic-sky130-nogl"
fi

# PATH helper
if ! grep -q 'export PATH="$HOME/.local/bin' "$HOME/.profile" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
fi
record DIR "$WORKDIR"
record DIR "$LOGDIR"
record DIR "$RC_DIR"

echo
echo "==== INSTALL SUMMARY ===="
command -v magic && ok "Magic installed"
echo "PDK: $PBASE/$PNAME"
echo "Manifest: $MANIFEST"
echo "Launchers: magic-sky130, magic-sky130-xsafe$( [ -x "$HOME/.local/bin/magic-sky130-nogl" ] && echo ", magic-sky130-nogl" )"
echo "Demo:  cd \"$DEMO_DIR\" && ngspice inverter_tt.spice"
