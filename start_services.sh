#!/bin/bash

# Change to the directory where this script is located, then move up one level (to kazza)
cd "$(dirname "$(readlink -f "$0")")/.." || exit

# Set the log file
LOGFILE="$(pwd)/ubuntu-start-services/start_services.log"
echo "$(date): Starting services..." | tee "$LOGFILE"

# Function to show desktop notification
show_notification() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"
    
    # Try different notification methods
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" "$title" "$message"
    elif command -v zenity >/dev/null 2>&1; then
        zenity --info --title="$title" --text="$message" --no-wrap &
    fi
}

# Function to log with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOGFILE"
}

# Show initial notification
show_notification "KAZZA Services" "Starting restaurant services..." "normal"

# ---- Handle ports without sudo ----
# Define ports
PORTS=(8000 8080)

log_message "Checking and managing ports..."

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

log_message "Starting backend..."

# ---- Start Backend (Django with Gunicorn) ----
cd restuarant_backend || { 
    log_message "ERROR: Failed to access restuarant_backend directory"
    show_notification "KAZZA Error" "Failed to access backend directory" "critical"
    exit 1
}

# Create virtual environment if needed
if [ ! -d "venv" ]; then
    log_message "Creating virtual environment with Python 3.12..."
    python3.12 -m venv venv >> "$LOGFILE" 2>&1
    if [ $? -ne 0 ]; then
        # Try with python3 if python3.12 is not available
        python3 -m venv venv >> "$LOGFILE" 2>&1
        if [ $? -ne 0 ]; then
            log_message "ERROR: Failed to create virtual environment"
            show_notification "KAZZA Error" "Failed to create virtual environment" "critical"
            exit 1
        fi
    fi
else
    log_message "Virtual environment already exists"
fi

if [ ! -f "venv/bin/activate" ]; then
    log_message "ERROR: Virtual environment is not set up correctly."
    show_notification "KAZZA Error" "Virtual environment setup failed" "critical"
    exit 1
fi

log_message "Installing backend dependencies..."
source venv/bin/activate

# Install/upgrade requirements including gunicorn
pip install -r requirements.txt >> "$LOGFILE" 2>&1
pip install gunicorn >> "$LOGFILE" 2>&1

# Set environment variables
export DB_DEFAULT=postgres
export DJANGO_SETTINGS_MODULE=config.settings

log_message "Running database migrations..."

# Run migrations
python manage.py migrate >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "ERROR: Migrations failed"
    show_notification "KAZZA Error" "Database migrations failed" "critical"
    exit 1
fi

log_message "Collecting static files..."

# Collect static files (important for production)
python manage.py collectstatic --noinput >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "ERROR: Collectstatic failed"
    show_notification "KAZZA Error" "Static files collection failed" "critical"
    exit 1
fi

log_message "Starting Django backend server..."

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
    show_notification "KAZZA Error" "Backend failed to start" "critical"
    exit 1
fi

# Test if backend is responding (with timeout)
if timeout 10 curl -s http://localhost:8000 >/dev/null 2>&1; then
    log_message "Backend is responding on port 8000"
else
    log_message "WARNING: Backend may not be fully ready yet"
fi

log_message "Backend started! Starting frontend..."

# Go back to the root KAZZA directory
cd ..

# ---- Start Frontend (Vue.js) ----
cd frontend || { 
    log_message "ERROR: Failed to access frontend directory"
    show_notification "KAZZA Error" "Failed to access frontend directory" "critical"
    exit 1
}

log_message "Starting Vue.js frontend..."

# Install dependencies
npm install >> "$LOGFILE" 2>&1
if [ $? -ne 0 ]; then
    log_message "ERROR: Frontend npm install failed"
    show_notification "KAZZA Error" "Frontend dependencies installation failed" "critical"
    exit 1
fi

log_message "Starting Vue.js development server..."

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
    show_notification "KAZZA Error" "Frontend failed to start" "critical"
    exit 1
fi

# Wait a bit more for services to fully initialize
sleep 3

log_message "All services started successfully!"
log_message "Backend running on: http://localhost:8000"
log_message "Frontend running on: http://localhost:8080"
log_message "Backend PID: $BACKEND_PID"
log_message "Frontend PID: $FRONTEND_PID"

# Show final success notification
show_notification "KAZZA Services Started" "✅ All services running successfully!

🔧 Backend: http://localhost:8000
🎨 Frontend: http://localhost:8080

Check log: $LOGFILE"

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

exit 0
