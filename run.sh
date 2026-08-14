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
flutter run -d chrome &
FRONTEND_PID=$!
cd ../../..

echo ""
echo "=========================================="
echo "  Both servers started!"
echo "=========================================="
echo "Backend PID: ${BACKEND_PID:-already running}"
echo "Frontend PID: $FRONTEND_PID"
echo ""
echo "Backend: http://localhost:5000"
echo "Frontend: Will open in Chrome"
echo ""
echo "Press Ctrl+C to stop both servers"
echo "=========================================="

# Wait for Ctrl+C
trap "kill ${BACKEND_PID:-} $FRONTEND_PID 2>/dev/null; exit" INT TERM

wait
