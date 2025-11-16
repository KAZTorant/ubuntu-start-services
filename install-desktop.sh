#!/bin/bash
# Simple installer for KAZZA Services desktop file

# Get the directory where this installer script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="$HOME"
USERNAME=$(whoami)

# Check if start_services.sh exists in the same directory
if [ ! -f "$SCRIPT_DIR/start_services.sh" ]; then
    echo "❌ Error: start_services.sh not found in $SCRIPT_DIR"
    echo "Please run this script from the ubuntu-start-services directory"
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

# Make desktop file executable
chmod +x "$USER_HOME/.local/share/applications/StartServicesKazza.desktop"

# Trust the desktop file
gio set "$USER_HOME/.local/share/applications/StartServicesKazza.desktop" metadata::trusted true 2>/dev/null || true

echo "✅ Desktop file installed successfully!"
echo "📱 You can now find 'Start KAZZA Services' in your applications menu"
echo "🖱️  Double-click it to start the services"

