#!/bin/bash
# Load nvm for GUI-launched apps
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Ensure npm/node is in PATH
export PATH="$NVM_DIR/versions/node/$(nvm version)/bin:$PATH"

# Change to the directory where this script is located, then move up one level (to kazza)
cd "$(dirname "$(readlink -f "$0")")/.." || exit

# Set the log file
LOGFILE="$(pwd)/ubuntu-start-services/start_services.log"
echo "$(date): Starting services..." | tee "$LOGFILE"

# Progress bar setup
PROGRESS_PIPE="/tmp/kazza_progress_$"
mkfifo "$PROGRESS_PIPE"

# Function to initialize progress dialog
init_progress() {
    if command -v zenity >/dev/null 2>&1; then
        zenity --progress \
            --title="KAZZA Xidmətləri" \
            --text="Xidmətlər işə salınır, bir az gözləyin..." \
            --percentage=0 \
            --auto-close \
            --no-cancel \
            --width=500 \
            --height=150 < "$PROGRESS_PIPE" &
        PROGRESS_PID=$!
        exec 3> "$PROGRESS_PIPE"
        PROGRESS_FD=3
    elif command -v kdialog >/dev/null 2>&1; then
        # KDE alternative
        PROGRESS_REF=$(kdialog --title "KAZZA Xidmətləri" --progressbar "Xidmətlər işə salınır, bir az gözləyin..." 100)
        PROGRESS_FD="kde"
    fi
}

# Function to update progress
update_progress() {
    local internal_message="$1"
    local percent="$2"
    local display_message="Xidmətlər işə salınır, bir az gözləyin..."
    
    if [ "$PROGRESS_FD" = "kde" ] && [ -n "$PROGRESS_REF" ]; then
        # KDE progress update
        kdialog --progressbar-set-label "$PROGRESS_REF" "$display_message"
        kdialog --progressbar-set-value "$PROGRESS_REF" "$percent"
    elif [ -n "$PROGRESS_FD" ] && [ "$PROGRESS_FD" != "kde" ]; then
        # Zenity progress update
        echo "$percent" >&$PROGRESS_FD
        echo "# $display_message" >&$PROGRESS_FD
    fi
    
    # Log the actual progress step in English for debugging
    log_message "[$percent%] $internal_message"
}

# Function to close progress dialog
close_progress() {
    if [ "$PROGRESS_FD" = "kde" ] && [ -n "$PROGRESS_REF" ]; then
        kdialog --progressbar-close "$PROGRESS_REF"
    elif [ -n "$PROGRESS_FD" ] && [ "$PROGRESS_FD" != "kde" ]; then
        exec 3>&-
        wait "$PROGRESS_PID" 2>/dev/null
    fi
    
    # Cleanup
    rm -f "$PROGRESS_PIPE"
    PROGRESS_FD=""
    PROGRESS_PID=""
    PROGRESS_REF=""
}

# Function to show desktop notification
show_notification() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"
    local timeout="${4:-10000}"  # Default 10 seconds
    
    # Try different notification methods
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" -t "$timeout" "$title" "$message"
    elif command -v zenity >/dev/null 2>&1; then
        zenity --info --title="$title" --text="$message" --no-wrap &
    elif command -v kdialog >/dev/null 2>&1; then
        kdialog --title "$title" --msgbox "$message" &
    fi
}

# Function to log with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOGFILE"
}

# Initialize progress dialog
init_progress
update_progress "Starting KAZZA Services..." 5

# ---- Handle ports without sudo ----
# Define ports
PORTS=(8000 8080)

update_progress "Checking and managing ports..." 10

# Loop through each port and kill processes using them (no sudo needed)
for port in "${PORTS[@]}"; do
    # Check if port is in use and kill each PID using it
    pids=$(lsof -ti tcp:$port 2>/dev/null)
    if [ -n "$pids" ]; then
        log_message "Port $port is in use by PIDs: $pids. Killing..."
        for pid in $pids; do
            log_message "Killing PID $pid"
            kill -9 "$pid" 2>/dev/null || kill -15 "$pid" 2>/dev/null
        done
        sleep 2
    else
        log_message "Port $port is available"
    fi
done

update_progress "Ports configured, accessing backend..." 15

# ---- Start Backend (Django with Gunicorn) ----
cd restuarant_backend || { 
    log_message "ERROR: Failed to access restuarant_backend directory"
    close_progress
    show_notification "KAZZA Error" "Failed to access backend directory" "critical" 15000
    exit 1
}

update_progress "Setting up Python environment..." 20

# Create virtual environment if needed
if [ ! -d "venv" ]; then
    log_message "Creating virtual environment with Python 3.12..."
    update_progress "Creating Python virtual environment..." 25
    python3.12 -m venv venv >> "$LOGFILE" 2>&1
    if [ $? -ne 0 ]; then
        # Try with python3 if python3.12 is not available
        python3 -m venv venv >> "$LOGFILE" 2>&1
        if [ $? -ne 0 ]; then
            log_message "ERROR: Failed to create virtual environment"
            close_progress
            show_notification "KAZZA Error" "Failed to create virtual environment" "critical" 15000
            exit 1
        fi
    fi
else
    log_message "Virtual environment already exists"
fi

if [ ! -f "venv/bin/activate" ]; then
    log_message "ERROR: Virtual environment is not set up correctly."
    close_progress
    show_notification "KAZZA Error" "Virtual environment setup failed" "critical" 15000
    exit 1
fi

update_progress "Installing backend dependencies..." 35

source venv/bin/activate

# Install/upgrade requirements including gunicorn
pip install -r requirements.txt >> "$LOGFILE" 2>&1
pip install gunicorn >> "$LOGFILE" 2>&1

# Set environment variables
export DB_DEFAULT=postgres
export DJANGO_SETTINGS_MODULE=config.settings

update_progress "Running database migrations..." 50

# Run migrations
python manage.py migrate >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "ERROR: Migrations failed"
    close_progress
    show_notification "KAZZA Error" "Database migrations failed" "critical" 15000
    exit 1
fi

update_progress "Collecting static files..." 60

# Collect static files (important for production)
python manage.py collectstatic --noinput >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "ERROR: Collectstatic failed"
    close_progress
    show_notification "KAZZA Error" "Static files collection failed" "critical" 15000
    exit 1
fi

update_progress "Starting Django backend server..." 70

# Start Gunicorn server in background
nohup gunicorn --bind 0.0.0.0:8000 --workers 3 --timeout 60 config.wsgi:application >> "$LOGFILE" 2>&1 &
BACKEND_PID=$!

# Save PIDs for later reference
echo "$BACKEND_PID" > ../ubuntu-start-services/backend.pid

# Wait a moment for backend to start and check if it's running
sleep 5

# Check if backend is running
if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
    log_message "ERROR: Backend failed to start"
    close_progress
    show_notification "KAZZA Error" "Backend failed to start" "critical" 15000
    exit 1
fi

update_progress "Backend started! Verifying connection..." 75

# Test if backend is responding (with timeout)
if timeout 10 curl -s http://localhost:8000 >/dev/null 2>&1; then
    log_message "Backend is responding on port 8000"
else
    log_message "WARNING: Backend may not be fully ready yet"
fi

update_progress "Backend ready! Starting frontend..." 80

# Go back to the root KAZZA directory
cd ..

# ---- Start Frontend (Vue.js) ----
cd frontend || { 
    log_message "ERROR: Failed to access frontend directory"
    close_progress
    show_notification "KAZZA Error" "Failed to access frontend directory" "critical" 15000
    exit 1
}

update_progress "Setting up frontend environment..." 85

# Install dependencies
npm install >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "ERROR: Frontend npm install failed"
    close_progress
    show_notification "KAZZA Error" "Frontend dependencies installation failed" "critical" 15000
    exit 1
fi

update_progress "Starting Vue.js development server..." 90

# Start frontend in background
nohup npm run serve >> "$LOGFILE" 2>&1 &
FRONTEND_PID=$!

# Save PIDs for later reference
echo "$FRONTEND_PID" > ../ubuntu-start-services/frontend.pid

cd ..

# Wait a moment for frontend to start
sleep 5

# Check if frontend is running
if ! kill -0 "$FRONTEND_PID" 2>/dev/null; then
    log_message "ERROR: Frontend failed to start"
    close_progress
    show_notification "KAZZA Error" "Frontend failed to start" "critical" 15000
    exit 1
fi

update_progress "Services initializing... Almost ready!" 95

# Wait a bit more for services to fully initialize
sleep 3

update_progress "All services started successfully!" 100

log_message "All services started successfully!"
log_message "Backend running on: http://localhost:8000"
log_message "Frontend running on: http://localhost:8080"
log_message "Backend PID: $BACKEND_PID"
log_message "Frontend PID: $FRONTEND_PID"

# Create a simple status file
cat > ubuntu-start-services/status.txt << EOF
KAZZA Services Status
====================
Started: $(date)
Backend PID: $BACKEND_PID
Frontend PID: $FRONTEND_PID
Backend URL: http://localhost:8000
Frontend URL: http://localhost:8080
Log File: $LOGFILE
EOF

# Wait a moment for progress bar to show completion
sleep 2

# Close progress dialog
close_progress

# Show final success notification that stays longer
show_notification "KAZZA Xidmətləri Uğurla Başladıldı! 🎉" "✅ Bütün xidmətlər indi işləyir:

🔧 Backend: http://localhost:8000
🎨 Frontend: http://localhost:8080

Xidmətlər arxa planda işləyir.
Ətraflı məlumat üçün status faylını yoxlayın." "normal" 30000

exit 0
