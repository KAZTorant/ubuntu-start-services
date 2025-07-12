#!/bin/bash

# Change to the directory where this script is located, then move up one level (to kazza)
cd "$(dirname "$(readlink -f "$0")")/.." || exit

# Set the log file
LOGFILE="$(pwd)/ubuntu-start-services/start_services.log"
echo "Starting services..." | tee "$LOGFILE"

# ---- Ensure necessary ports are open ----
# Define ports (removed 3000 for printer service)
PORTS=(8000 8080)

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

# ---- Start Backend (Django with Gunicorn) ----
cd restaurant_backend || { echo "Failed to access restaurant_backend directory" | tee -a "$LOGFILE"; exit 1; }

# Create virtual environment if needed
if [ ! -d "venv" ]; then
    echo "Creating virtual environment with Python 3.12..." | tee -a "$LOGFILE"
    python3.12 -m venv venv >> "$LOGFILE" 2>&1
    if [ $? -ne 0 ]; then
        echo "Failed to create virtual environment" | tee -a "$LOGFILE"
        exit 1
    fi
else
    echo "Virtual environment already exists" | tee -a "$LOGFILE"
fi

if [ ! -f "venv/bin/activate" ]; then
    echo "Virtual environment is not set up correctly." | tee -a "$LOGFILE"
    exit 1
fi

echo "Starting Django backend with Gunicorn..." | tee -a "$LOGFILE"
source venv/bin/activate

# Install/upgrade requirements including gunicorn
pip install -r requirements.txt >> "$LOGFILE" 2>&1
pip install gunicorn >> "$LOGFILE" 2>&1

# Set environment variables
export DB_DEFAULT=postgres
export DJANGO_SETTINGS_MODULE=restaurant_backend.settings

# Run migrations
python manage.py migrate >> "$LOGFILE" 2>&1

# Collect static files (important for production)
python manage.py collectstatic --noinput >> "$LOGFILE" 2>&1

# Start Gunicorn server
# Adjust the module name based on your project structure (restaurant_backend.wsgi)
nohup bash -c "gunicorn --bind 0.0.0.0:8000 --workers 3 --timeout 60 restaurant_backend.wsgi:application" >> "$LOGFILE" 2>&1 &

cd ..

# ---- Start Frontend (Vue.js) ----
cd frontend || { echo "Failed to access frontend directory" | tee -a "$LOGFILE"; exit 1; }

echo "Starting Vue.js frontend..." | tee -a "$LOGFILE"
npm install >> "$LOGFILE" 2>&1
nohup bash -c "npm run serve" >> "$LOGFILE" 2>&1 &

cd ..

echo "All services started successfully!" | tee -a "$LOGFILE"
echo "Backend running on: http://localhost:8000" | tee -a "$LOGFILE"
echo "Frontend running on: http://localhost:8080" | tee -a "$LOGFILE"

# Notify the user with a pop-up (requires zenity)
command -v zenity >/dev/null 2>&1 && zenity --info --title="Service Status" --text="Backend (Gunicorn) and Frontend services are up!\n\nBackend: http://localhost:8000\nFrontend: http://localhost:8080" &

exit 0
