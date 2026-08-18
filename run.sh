#!/bin/bash

# ERP Billing System - Start Script
# This script starts both backend and frontend servers

echo "=========================================="
echo "  Starting ERP Billing System"
echo "=========================================="
echo ""

# Start Backend (Flask)
echo "Starting Backend (Flask) on port 5000..."
cd billing_system/backend

BACKEND_PID=""
if curl -s -m 3 http://localhost:5000/health >/dev/null 2>&1; then
  echo "Backend already running on port 5000 — reusing it."
else
  python app.py &
  BACKEND_PID=$!
  # Wait a moment for backend to start
  sleep 2
fi

cd ../..

# Start Frontend (Flutter)
echo "Starting Frontend (Flutter)..."
cd billing_system/frontend/flutter_application

# Clean old pid file if exists
rm -f flutter_app.pid

# Start Flutter run with a pid file so we can trigger Hot Reload programmatically
flutter run -d chrome --pid-file flutter_app.pid &
FRONTEND_PID=$!

# Start Python file watcher for auto-reload on file changes
python watch.py lib flutter_app.pid &
WATCHER_PID=$!

cd ../../..

echo ""
echo "=========================================="
echo "  Both servers started!"
echo "=========================================="
echo "Backend PID: ${BACKEND_PID:-already running}"
echo "Frontend PID: $FRONTEND_PID"
echo "Watcher PID: $WATCHER_PID"
echo ""
echo "Backend: http://localhost:5000"
echo "Frontend: Will open in Chrome"
echo "Auto Hot-Reload: Enabled (watches lib/ for .dart file changes)"
echo ""
echo "Press Ctrl+C to stop both servers"
echo "=========================================="

# Wait for Ctrl+C
trap "kill ${BACKEND_PID:-} $FRONTEND_PID $WATCHER_PID 2>/dev/null; rm -f billing_system/frontend/flutter_application/flutter_app.pid; exit" INT TERM

wait
