#!/bin/bash

# Change to the directory where this script is located, then move up one level (to kazza)
cd "$(dirname "$(readlink -f "$0")")/.." || exit

# Set the log file
LOGFILE="$(pwd)/ubuntu-start-services/start_services.log"
echo "Starting services..." | tee "$LOGFILE"

# ---- Ensure necessary ports are open ----
# Define ports
PORTS=(8000 3000 8080)

# Loop through each port and ensure it's open, and kill any process using it
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


# ---- Start Backend (Django) ----
cd managements || { echo "Failed to access managements directory" | tee -a "$LOGFILE"; exit 1; }

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

echo "Starting Django backend..." | tee -a "$LOGFILE"
source venv/bin/activate
pip install -r requirements.txt >> "$LOGFILE" 2>&1
export DB_DEFAULT=postgres
python manage.py migrate >> "$LOGFILE" 2>&1
nohup bash -c "python manage.py runserver 0.0.0.0:8000" >> "$LOGFILE" 2>&1 &

cd ..

# ---- Start Printer Service ----
cd printer-v2 || { echo "Failed to access printer-v2 directory" | tee -a "$LOGFILE"; exit 1; }

echo "Starting Printer service..." | tee -a "$LOGFILE"
npm install >> "$LOGFILE" 2>&1
nohup bash -c "export PORT=3000 && npm run start" >> "$LOGFILE" 2>&1 &

cd ..

# ---- Start Frontend (Vue.js) ----
cd frontend || { echo "Failed to access frontend directory" | tee -a "$LOGFILE"; exit 1; }

echo "Starting Vue.js frontend..." | tee -a "$LOGFILE"
npm install >> "$LOGFILE" 2>&1
nohup bash -c "npm run serve" >> "$LOGFILE" 2>&1 &

cd ..

echo "All services started successfully!" | tee -a "$LOGFILE"

# Notify the user with a pop-up (requires zenity)
command -v zenity >/dev/null 2>&1 && zenity --info --title="Service Status" --text="All services are up!" &

exit 0
