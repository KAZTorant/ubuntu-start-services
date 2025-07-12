#!/bin/bash

# Change to the directory where this script is located, then move up one level (to kazza)
cd "$(dirname "$(readlink -f "$0")")/.." || exit

# Set the log file
LOGFILE="$(pwd)/ubuntu-start-services/start_services.log"
echo "Starting services..." | tee "$LOGFILE"

# Function to show progress popup
show_progress() {
    local message="$1"
    local percent="$2"
    echo "$percent" | zenity --progress \
        --title="Starting KAZZA Services" \
        --text="$message" \
        --percentage="$percent" \
        --auto-close \
        --no-cancel &
    PROGRESS_PID=$!
}

# Function to update progress
update_progress() {
    local message="$1"
    local percent="$2"
    if command -v zenity >/dev/null 2>&1; then
        # Kill previous progress dialog if it exists
        if [ -n "$PROGRESS_PID" ]; then
            kill "$PROGRESS_PID" 2>/dev/null
        fi
        # Show new progress
        (
            echo "$percent"
            echo "# $message"
            sleep 2
        ) | zenity --progress \
            --title="Starting KAZZA Services" \
            --text="$message" \
            --percentage="$percent" \
            --auto-close \
            --no-cancel &
        PROGRESS_PID=$!
    fi
}

# Function to show final notification
show_notification() {
    local title="$1"
    local message="$2"
    local icon="$3"
    if command -v zenity >/dev/null 2>&1; then
        zenity --notification \
            --window-icon="$icon" \
            --text="$title: $message" &
        zenity --info \
            --title="$title" \
            --text="$message" \
            --width=400 \
            --height=200 &
    fi
}

# Start initial progress
update_progress "Initializing services..." 10

# ---- Ensure necessary ports are open ----
# Define ports (removed 3000 for printer service)
PORTS=(8000 8080)

update_progress "Checking and opening ports..." 20

# Loop through each port and ensure it's open, and kill any process using it
for port in "${PORTS[@]}"; do
    # Check if the port is already allowed
    if ! sudo ufw status | grep -q "ALLOW.*$port"; then
        echo "Opening port $port..." | tee -a "$LOGFILE"
        sudo ufw allow $port >> "$LOGFILE" 2>&1
    else
        echo "Port $port is already open." | tee -a "$LOGFILE"
    fi

    # Check if port is in use and kill each PID using it
    pids=$(lsof -ti tcp:$port)
    if [ -n "$pids" ]; then
        echo "Port $port is in use by PIDs: $pids. Killing..." | tee -a "$LOGFILE"
        for pid in $pids; do
            echo "Killing PID $pid" | tee -a "$LOGFILE"
            kill -9 "$pid" >> "$LOGFILE" 2>&1
        done
    fi
done
sleep 3

update_progress "Ports configured. Starting backend..." 35

# ---- Start Backend (Django with Gunicorn) ----
# If Django project is in the root directory, comment out the cd line
# cd managements || { echo "Failed to access backend directory" | tee -a "$LOGFILE"; exit 1; }

# Create virtual environment if needed
if [ ! -d "venv" ]; then
    echo "Creating virtual environment with Python 3.12..." | tee -a "$LOGFILE"
    update_progress "Creating Python virtual environment..." 40
    python3.12 -m venv venv >> "$LOGFILE" 2>&1
    if [ $? -ne 0 ]; then
        echo "Failed to create virtual environment" | tee -a "$LOGFILE"
        show_notification "Error" "Failed to create virtual environment. Check log file." "error"
        exit 1
    fi
else
    echo "Virtual environment already exists" | tee -a "$LOGFILE"
fi

if [ ! -f "venv/bin/activate" ]; then
    echo "Virtual environment is not set up correctly." | tee -a "$LOGFILE"
    show_notification "Error" "Virtual environment is not set up correctly." "error"
    exit 1
fi

update_progress "Installing backend dependencies..." 50

echo "Starting Django backend with Gunicorn..." | tee -a "$LOGFILE"
source venv/bin/activate

# Install/upgrade requirements including gunicorn
pip install -r requirements.txt >> "$LOGFILE" 2>&1
pip install gunicorn >> "$LOGFILE" 2>&1

# Set environment variables
export DB_DEFAULT=postgres
export DJANGO_SETTINGS_MODULE=restaurant_backend.settings

update_progress "Running database migrations..." 60

# Run migrations
python manage.py migrate >> "$LOGFILE" 2>&1

update_progress "Collecting static files..." 65

# Collect static files (important for production)
python manage.py collectstatic --noinput >> "$LOGFILE" 2>&1

update_progress "Starting Django backend server..." 70

# Start Gunicorn server
# Adjust the module name based on your project structure (restaurant_backend.wsgi)
nohup bash -c "gunicorn --bind 0.0.0.0:8000 --workers 3 --timeout 60 restaurant_backend.wsgi:application" >> "$LOGFILE" 2>&1 &

# Wait a moment for backend to start
sleep 3

update_progress "Backend started! Starting frontend..." 80

# ---- Start Frontend (Vue.js) ----
cd frontend || { 
    echo "Failed to access frontend directory" | tee -a "$LOGFILE"
    show_notification "Error" "Failed to access frontend directory. Check log file." "error"
    exit 1
}

echo "Starting Vue.js frontend..." | tee -a "$LOGFILE"

update_progress "Installing frontend dependencies..." 85

npm install >> "$LOGFILE" 2>&1

update_progress "Starting Vue.js development server..." 90

nohup bash -c "npm run serve" >> "$LOGFILE" 2>&1 &

cd ..

# Wait a moment for frontend to start
sleep 5

update_progress "Services starting up... Almost ready!" 95

# Wait a bit more for services to fully initialize
sleep 3

update_progress "All services started successfully!" 100

echo "All services started successfully!" | tee -a "$LOGFILE"
echo "Backend running on: http://localhost:8000" | tee -a "$LOGFILE"
echo "Frontend running on: http://localhost:8080" | tee -a "$LOGFILE"

# Close progress dialog
if [ -n "$PROGRESS_PID" ]; then
    kill "$PROGRESS_PID" 2>/dev/null
fi

# Show final success notification
show_notification "KAZZA Services Started" "✅ All services are running successfully!

🔧 Backend: http://localhost:8000
🎨 Frontend: http://localhost:8080

Services are running in the background." "dialog-information"

exit 0
