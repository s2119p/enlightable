#!/usr/bin/env sh
set -eu

PKG="hfs"
PKG_SPEC="hfs@latest"
PREFIX="/usr/local"
BIN_DIR="$PREFIX/bin"
NODE_MODULES_DIR="$PREFIX/lib/node_modules"
TARGET_BIN="$BIN_DIR/hfs"

# Helpers
error() { echo "ERROR: $*" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Ensure npm exists
command_exists npm || error "npm not found; install nodejs/npm first (apk add nodejs npm)"

# Get installed version (if any)
installed_version() {
  if [ -d "$NODE_MODULES_DIR/$PKG" ]; then
    # prefer package.json version if present
    if [ -f "$NODE_MODULES_DIR/$PKG/package.json" ]; then
      awk -F\" '/"version":/ {print $4; exit}' "$NODE_MODULES_DIR/$PKG/package.json" || true
    else
      true
    fi
  fi
}

# Get latest published version from npm registry (uses npm view)
latest_version() {
  npm view "$PKG" version --silent 2>/dev/null || true
}

cleanup_tmp() {
  npm cache clean --force 2>/dev/null || true
  rm -rf /tmp/_npx* /tmp/npm-* 2>/dev/null || true
}

ensure_symlink() {
  # If npm already created a wrapper in $BIN_DIR, trust it. Otherwise create symlink to package entry.
  if [ -L "$TARGET_BIN" ] || [ -x "$TARGET_BIN" ]; then
    # If it's a file (not symlink) leave it. If symlink, ensure target exists.
    if [ -L "$TARGET_BIN" ]; then
      real=$(readlink -f "$TARGET_BIN" 2>/dev/null || true)
      if [ -z "$real" ] || [ ! -e "$real" ]; then
        ln -sf "../lib/node_modules/$PKG/src/index.js" "$TARGET_BIN"
        chmod +x "$TARGET_BIN" || true
      fi
    fi
  else
    ln -sf "../lib/node_modules/$PKG/src/index.js" "$TARGET_BIN"
    chmod +x "$TARGET_BIN" || true
  fi
}

main() {
  echo "Checking hfs installation..."
  cur="$(installed_version || true)"
  latest="$(latest_version || true)"

  if [ -z "$cur" ]; then
    echo "hfs not installed; installing $PKG_SPEC..."
    npm install -g "$PKG_SPEC" --no-audit --no-fund --unsafe-perm --loglevel=error
    ensure_symlink
    cleanup_tmp
    echo "Installed hfs at: $(readlink -f "$TARGET_BIN")"
    exit 0
  fi

  if [ -z "$latest" ]; then
    echo "Could not determine latest hfs version from registry; performing npm install to be safe..."
    npm install -g "$PKG_SPEC" --no-audit --no-fund --unsafe-perm --loglevel=error
    ensure_symlink
    cleanup_tmp
    echo "Done. hfs at: $(readlink -f "$TARGET_BIN")"
    exit 0
  fi

  if [ "$cur" = "$latest" ]; then
    echo "hfs is up-to-date (version $cur). No action needed."
    ensure_symlink
    cleanup_tmp
    exit 0
  fi

  echo "Installed hfs version: $cur; latest available: $latest"
  echo "Upgrading to $latest..."
  npm install -g "$PKG_SPEC" --no-audit --no-fund --unsafe-perm --loglevel=error
  ensure_symlink
  cleanup_tmp
  echo "Upgraded hfs to $(readlink -f "$TARGET_BIN")"
}

main "$@"
