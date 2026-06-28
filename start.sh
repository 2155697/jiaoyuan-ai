#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
if ! pgrep -x "ollama" > /dev/null; then
    echo "启动Ollama..."
    ollama serve &
    sleep 3
fi
echo "启动教员AI顾问..."
cd "$PROJECT_DIR"
python3 "$PROJECT_DIR/src/chat_app.py"
