#!/bin/bash
# Change to the directory where this script is located, then move up one level (to kazza)
cd "$(dirname "$(readlink -f "$0")")/.." || exit

# Set the log file (placed inside helper-ubuntu)
LOGFILE="$(pwd)/helper-ubuntu/start_services.log"
echo "Starting services..." > "$LOGFILE"

# ---- Start Backend (Django) ----
cd managements || { echo "Failed to access managements directory" >> "$LOGFILE"; exit 1; }

# Create virtual environment if needed
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..." >> "$LOGFILE"
    python3 -m venv venv >> "$LOGFILE" 2>&1
fi

nohup bash -c "
    cd $(pwd) &&
    source venv/bin/activate &&
    pip install -r requirements.txt &&
    export DB_DEFAULT=postgres &&
    python manage.py runserver 0.0.0.0:8000
" >> "$LOGFILE" 2>&1 & disown

cd ..

# ---- Start Frontend (Vue.js) ----
cd frontend || { echo "Failed to access frontend directory" >> "$LOGFILE"; exit 1; }
nohup bash -c "
    cd $(pwd) &&
    npm install &&
    npm run serve
" >> "$LOGFILE" 2>&1 & disown
cd ..

# ---- Start Printer Service ----
cd printer-v2 || { echo "Failed to access printer-v2 directory" >> "$LOGFILE"; exit 1; }
nohup bash -c "
    cd $(pwd) &&
    npm install &&
    npm run start
" >> "$LOGFILE" 2>&1 & disown
cd ..

echo "All services started successfully!" >> "$LOGFILE"

# Notify the user with a pop-up (requires zenity)
zenity --info --title="Service Status" --text="All services are up!" &

exit 0
