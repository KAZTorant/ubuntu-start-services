#!/bin/bash
# Simple installer for KAZZA Services desktop file

set -e  # Exit on error

# Get the directory where this installer script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="$HOME"

echo "🔧 KAZZA xidmətlərinin desktop faylı quraşdırılır..."

# Check if start_services.sh exists in the same directory
if [ ! -f "$SCRIPT_DIR/start_services.sh" ]; then
    echo "❌ Error: start_services.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Check if desktop file exists
if [ ! -f "$SCRIPT_DIR/StartServicesKazza.desktop" ]; then
    echo "❌ Error: StartServicesKazza.desktop not found in $SCRIPT_DIR"
    exit 1
fi

# Make script executable
chmod +x "$SCRIPT_DIR/start_services.sh"

# Create applications directory if it doesn't exist
mkdir -p "$USER_HOME/.local/share/applications"

# Copy desktop file and replace USERNAME placeholder with actual paths
sed "s|/home/USERNAME|$USER_HOME|g" "$SCRIPT_DIR/StartServicesKazza.desktop" > "$USER_HOME/.local/share/applications/StartServicesKazza.desktop"

# Make desktop file executable (chmod 755)
chmod 755 "$USER_HOME/.local/share/applications/StartServicesKazza.desktop"

# Trust the desktop file (required for Ubuntu 20+)
if command -v gio >/dev/null 2>&1; then
    gio set "$USER_HOME/.local/share/applications/StartServicesKazza.desktop" metadata::trusted true 2>/dev/null || true
fi

# Update desktop database to refresh applications menu
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$USER_HOME/.local/share/applications" 2>/dev/null || true
fi

echo ""
echo "✅ Desktop faylı uğurla quraşdırıldı!"
echo "📱 İndi tətbiq menyusunda 'Sistemi başlat' tapa bilərsiniz"
echo "🖱️  Xidmətləri işə salmaq üçün üzərinə 2 dəfə klikləyin"
echo ""
echo "📂 Quraşdırıldı: $USER_HOME/.local/share/applications/StartServicesKazza.desktop"

