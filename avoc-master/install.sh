#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
MINIFORGE_VERSION="24.11.2-1"
MINIFORGE_INSTALLER="Miniforge3-${MINIFORGE_VERSION}-Linux-x86_64.sh"
MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${MINIFORGE_INSTALLER}"

# Parse arguments
PREFIX=""
CREATE_DESKTOP_SHORTCUT=0
NO_SHORTCUTS=0
SKIP_CONNECTIVITY_CHECK=0

usage() {
    cat << 'USAGE'
Usage: ./install.sh --prefix <folder> [options]

Installs AVoc with bundled Python 3.12 (via Miniforge). No system Python required.
Everything is self-contained in the prefix folder.

Options:
  --prefix <folder>          Target install folder (required)
  --desktop-shortcut         Create .desktop launcher in ~/.local/share/applications
  --no-shortcuts             Skip desktop integration (default)
  --skip-connectivity-check  Skip PyPI connectivity test
  -h, --help                 Show this help

Examples:
  ./install.sh --prefix "$HOME/.local/opt/avoc"
  ./install.sh --prefix "$HOME/.local/opt/avoc" --no-shortcuts
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            [[ $# -ge 2 ]] || { echo "error: --prefix requires a value" >&2; exit 1; }
            PREFIX="$2"
            shift 2
            ;;
        --desktop-shortcut)
            CREATE_DESKTOP_SHORTCUT=1
            shift
            ;;
        --no-shortcuts)
            NO_SHORTCUTS=1
            shift
            ;;
        --skip-connectivity-check)
            SKIP_CONNECTIVITY_CHECK=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

[[ -n "${PREFIX}" ]] || { echo "error: --prefix is required" >&2; usage >&2; exit 1; }

if [[ "${CREATE_DESKTOP_SHORTCUT}" -eq 1 && "${NO_SHORTCUTS}" -eq 1 ]]; then
    echo "error: --desktop-shortcut and --no-shortcuts are mutually exclusive" >&2
    exit 1
fi

# Resolve absolute path
if command -v python3 &>/dev/null; then
    PREFIX="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$PREFIX")"
else
    PREFIX="$(cd "$PREFIX" 2>/dev/null && pwd)" || PREFIX="$(readlink -f "$PREFIX" 2>/dev/null)" || PREFIX="$PREFIX"
fi

# Define paths
CONDA_DIR="${PREFIX}/.conda"
CONDA_INSTALLER_DIR="${PREFIX}/.conda-installer"
VENV_DIR="${PREFIX}/.venv"
APP_DIR="${PREFIX}/app"
BIN_DIR="${PREFIX}/bin"
DATA_DIR="${PREFIX}/data"
MANIFEST_PATH="${PREFIX}/install-manifest.txt"
INSTALLER_PATH="${CONDA_INSTALLER_DIR}/${MINIFORGE_INSTALLER}"

echo "=============================================="
echo "AVoc Portable Installer (with Bundled Python)"
echo "=============================================="
echo ""
echo "Install prefix: ${PREFIX}"
echo ""

# Create directory structure
mkdir -p "${PREFIX}" "${BIN_DIR}" "${DATA_DIR}" "${CONDA_INSTALLER_DIR}"

# Download Miniforge if not present
if [[ -f "${INSTALLER_PATH}" ]]; then
    echo "Miniforge installer already present, skipping download."
else
    echo "Downloading Miniforge ${MINIFORGE_VERSION}..."
    
    if command -v wget &>/dev/null; then
        wget --show-progress -O "${INSTALLER_PATH}.tmp" "${MINIFORGE_URL}"
        mv "${INSTALLER_PATH}.tmp" "${INSTALLER_PATH}"
    elif command -v curl &>/dev/null; then
        curl -L --progress-bar -o "${INSTALLER_PATH}.tmp" "${MINIFORGE_URL}"
        mv "${INSTALLER_PATH}.tmp" "${INSTALLER_PATH}"
    else
        echo "error: wget or curl required to download Miniforge" >&2
        exit 1
    fi
    
    echo "Downloaded: ${INSTALLER_PATH}"
fi

# Verify installer integrity (basic size check)
INSTALLER_SIZE=$(stat -c%s "${INSTALLER_PATH}" 2>/dev/null || stat -f%z "${INSTALLER_PATH}" 2>/dev/null || echo "0")
if [[ "${INSTALLER_SIZE}" -lt 50000000 ]]; then
    echo "error: Miniforge installer appears corrupted (size: ${INSTALLER_SIZE} bytes)" >&2
    exit 1
fi

# Install Miniforge (batch mode, no PATH/shell modifications)
echo ""
echo "Installing Miniforge to ${CONDA_DIR}..."
echo "  - No system PATH modifications"
echo "  - No shell profile changes"
echo ""

bash "${INSTALLER_PATH}" -b -p "${CONDA_DIR}"

# Force conda to keep package cache inside our tree
export CONDA_PKGS_DIRS="${CONDA_DIR}/pkgs"

# Create Python 3.12 environment
echo ""
echo "Creating Python 3.12 environment..."
"${CONDA_DIR}/bin/conda" create -y -p "${VENV_DIR}" python=3.12

PYTHON="${VENV_DIR}/bin/python"
PYTHON_VERSION="$(${PYTHON} -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')"

echo ""
echo "Python ${PYTHON_VERSION} installed at: ${PYTHON}"

# Connectivity check
CONNECTIVITY_STATUS="ok"
if [[ "${SKIP_CONNECTIVITY_CHECK}" -eq 0 ]]; then
    if ! ${PYTHON} -c 'import socket; s=socket.create_connection(("pypi.org", 443), timeout=5); s.close()' 2>/dev/null; then
        echo ""
        echo "WARNING: Cannot reach pypi.org. Installation may fail if packages not cached." >&2
        CONNECTIVITY_STATUS="failed"
    fi
fi

echo ""
echo "Installing AVoc dependencies..."
"${PYTHON}" -m pip install --upgrade pip --quiet
"${VENV_DIR}/bin/pip" install -r "${SCRIPT_DIR}/requirements-3.12.3.txt"

# Copy application files
echo ""
echo "Copying application files..."
if [[ -d "${APP_DIR}" ]]; then
    rm -rf "${APP_DIR}"
fi
mkdir -p "${APP_DIR}"

cp -a "${SCRIPT_DIR}/main.py" "${APP_DIR}/"
cp -a "${SCRIPT_DIR}/src" "${APP_DIR}/"
cp -a "${SCRIPT_DIR}/LICENSE" "${APP_DIR}/"
cp -a "${SCRIPT_DIR}/README.md" "${APP_DIR}/"

# Create launcher script
cat > "${BIN_DIR}/avoc" << 'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export AVOC_HOME="${AVOC_HOME:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"
export AVOC_DATA_DIR="${AVOC_DATA_DIR:-${AVOC_HOME}/data}"

# Ensure data directories exist
mkdir -p \
    "${AVOC_DATA_DIR}" \
    "${AVOC_DATA_DIR}/settings" \
    "${AVOC_DATA_DIR}/cache" \
    "${AVOC_DATA_DIR}/logs" \
    "${AVOC_DATA_DIR}/models" \
    "${AVOC_DATA_DIR}/pretrain" \
    "${AVOC_DATA_DIR}/voice_cards"

# Redirect XDG paths to portable locations
export XDG_DATA_HOME="${AVOC_DATA_DIR}"
export XDG_CONFIG_HOME="${AVOC_DATA_DIR}/settings"
export XDG_CACHE_HOME="${AVOC_DATA_DIR}/cache"
export XDG_STATE_HOME="${AVOC_DATA_DIR}/logs"

exec "${AVOC_HOME}/.venv/bin/python" "${AVOC_HOME}/app/main.py" "$@"
LAUNCHER

chmod +x "${BIN_DIR}/avoc"

# Create uninstaller
cat > "${BIN_DIR}/uninstall" << UNINSTALL
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${PREFIX}"
MANIFEST="${MANIFEST_PATH}"

if [[ ! -d "\${ROOT_DIR}" ]]; then
    echo "Install root already removed: \${ROOT_DIR}"
    exit 0
fi

# Confirmation prompt
if [[ "\${1:-}" != "--yes" ]]; then
    echo "This will uninstall AVoc by removing:"
    echo "  \${ROOT_DIR}"
    echo ""
    
    if [[ -f "\${MANIFEST}" ]]; then
        echo "The following shortcuts will also be removed:"
        cat "\${MANIFEST}" | sed 's/^/  /'
        echo ""
    fi
    
    read -r -p "Type 'yes' to continue: " confirm
    if [[ "\${confirm}" != "yes" ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Remove shortcuts listed in manifest
if [[ -f "\${MANIFEST}" ]]; then
    while IFS= read -r shortcut_path || [[ -n "\${shortcut_path}" ]]; do
        [[ -n "\${shortcut_path}" ]] || continue
        if [[ -e "\${shortcut_path}" ]]; then
            rm -f "\${shortcut_path}"
            echo "Removed: \${shortcut_path}"
        fi
    done < "\${MANIFEST}"
    rm -f "\${MANIFEST}"
fi

# Remove install root (includes .conda, .conda-installer, .venv, app, data, bin)
rm -rf "\${ROOT_DIR}"
echo ""
echo "AVoc has been completely uninstalled."
echo "Removed: \${ROOT_DIR}"
UNINSTALL

chmod +x "${BIN_DIR}/uninstall"

# Create metadata
cat > "${PREFIX}/install-metadata.json" << META
{
  "installer": "install.sh",
  "installed_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "prefix": "${PREFIX}",
  "python_version": "${PYTHON_VERSION}",
  "python_source": "bundled",
  "miniforge_version": "${MINIFORGE_VERSION}",
  "miniforge_installer": "${MINIFORGE_INSTALLER}",
  "miniforge_path": "${CONDA_INSTALLER_DIR}/${MINIFORGE_INSTALLER}",
  "conda_root": "${CONDA_DIR}",
  "venv": ".venv",
  "launcher": "bin/avoc",
  "uninstaller": "bin/uninstall",
  "data_dir": "data",
  "requirements": "requirements-3.12.3.txt"
}
META

# Desktop shortcut
if [[ "${CREATE_DESKTOP_SHORTCUT}" -eq 1 ]]; then
    DESKTOP_FILE="${HOME}/.local/share/applications/AVoc.desktop"
    mkdir -p "$(dirname "${DESKTOP_FILE}")"
    
    cat > "${DESKTOP_FILE}" << DESKTOP
[Desktop Entry]
Name=AVoc
Comment=Local Realtime Voice Changer
Exec=${BIN_DIR}/avoc
Icon=${APP_DIR}/src/avoc/AVoc.svg
Type=Application
Categories=AudioVideo;Audio;
Terminal=false
Path=${PREFIX}

DESKTOP
    
    chmod +x "${DESKTOP_FILE}"
    printf '%s\n' "${DESKTOP_FILE}" > "${MANIFEST_PATH}"
    echo "Created desktop shortcut: ${DESKTOP_FILE}"
fi

echo ""
echo "=============================================="
echo "Installation Complete!"
echo "=============================================="
echo ""
echo "Location:     ${PREFIX}"
echo "Python:       ${PYTHON_VERSION} (bundled)"
echo "Launcher:     ${BIN_DIR}/avoc"
echo ""
echo "To run AVoc:"
echo "  ${BIN_DIR}/avoc"
echo ""
echo "To uninstall:"
echo "  ${BIN_DIR}/uninstall"
echo "  # or simply delete: ${PREFIX}"
echo ""
echo "Note: Miniforge installer kept at:"
echo "  ${CONDA_INSTALLER_DIR}/${MINIFORGE_INSTALLER}"
echo "=============================================="