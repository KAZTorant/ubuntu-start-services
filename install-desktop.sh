#!/bin/bash
# Simple installer for KAZZA Services desktop file

# Get the current user's home directory
USER_HOME="$HOME"
USERNAME=$(whoami)

# Make script executable
chmod +x "$USER_HOME/Desktop/KAZZA/ubuntu-start-services/start_services.sh"

# Create applications directory if it doesn't exist
mkdir -p "$USER_HOME/.local/share/applications"

# Copy desktop file and replace USERNAME placeholder
sed "s|USERNAME|$USERNAME|g" "$USER_HOME/Desktop/KAZZA/ubuntu-start-services/StartServicesKazza.desktop" > "$USER_HOME/.local/share/applications/StartServicesKazza.desktop"

# Make desktop file executable
chmod +x "$USER_HOME/.local/share/applications/StartServicesKazza.desktop"

# Trust the desktop file
gio set "$USER_HOME/.local/share/applications/StartServicesKazza.desktop" metadata::trusted true 2>/dev/null || true

echo "✅ Desktop file installed successfully!"
echo "📱 You can now find 'Start KAZZA Services' in your applications menu"
echo "🖱️  Double-click it to start the services"

