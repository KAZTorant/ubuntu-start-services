#!/bin/bash

# Log file location (in the same folder)
LOGFILE="$(dirname "$0")/start_services.log"

# Function to report an error
report_error() {
    echo "Error occurred: $1" >> "$LOGFILE"
}

# Navigate to the script's directory (main folder)
cd "$(dirname "$0")" || exit

# ---- Start Backend (Django) ----
cd managements || exit

# Check if venv directory exists
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..." >> "$LOGFILE"
    python3 -m venv venv
fi

nohup bash -c "
    cd $(pwd) &&
    source venv/bin/activate &&
    pip install -r requirements.txt &&
    export DB_DEFAULT=postgres &&
    python manage.py runserver 0.0.0.0:8000
" >> "$LOGFILE" 2>&1 & disown

# Navigate back to the main folder
cd ..

# ---- Start Frontend (Vue.js) ----
cd frontend || exit

nohup bash -c "
    cd $(pwd) &&
    npm install &&
    npm run serve
" >> "$LOGFILE" 2>&1 & disown

# Navigate back to the main folder
cd ..

# ---- Start Printer Service ----
cd printer-v2 || exit

nohup bash -c "
    cd $(pwd) &&
    npm install &&
    npm run start
" >> "$LOGFILE" 2>&1 & disown

# Navigate back to the main folder
cd ..

echo "All services started successfully!" >> "$LOGFILE"

exit 0
