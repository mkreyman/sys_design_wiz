#!/bin/bash
# Setup script for competition starter template
# Usage: ./setup.sh YourProjectName

if [ -z "$1" ]; then
    echo "Usage: ./setup.sh YourProjectName"
    echo "Example: ./setup.sh TravelAssistant"
    exit 1
fi

PROJECT_NAME=$1
PROJECT_SNAKE=$(echo "$PROJECT_NAME" | sed -E 's/([A-Z])/_\1/g' | sed 's/^_//' | tr '[:upper:]' '[:lower:]')

echo "Setting up project: $PROJECT_NAME ($PROJECT_SNAKE)"

# Rename directories
if [ -d "lib/template_app" ]; then
    mv lib/template_app "lib/$PROJECT_SNAKE"
fi

if [ -d "lib/template_app_web" ]; then
    mv lib/template_app_web "lib/${PROJECT_SNAKE}_web"
fi

# Replace in all files
find . -type f \( -name "*.ex" -o -name "*.exs" -o -name "*.md" -o -name "*.json" \) -exec sed -i '' \
    -e "s/TemplateApp/$PROJECT_NAME/g" \
    -e "s/template_app/$PROJECT_SNAKE/g" \
    {} \;

# Install pre-commit hook
if [ -d ".git" ]; then
    cp hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    echo "Pre-commit hook installed"
else
    echo "Git not initialized - run 'git init' then copy hooks/pre-commit to .git/hooks/"
fi

echo ""
echo "Setup complete! Next steps:"
echo "1. git init (if not done)"
echo "2. Add OPENAI_API_KEY to .env or config"
echo "3. mix deps.get"
echo "4. mix dialyzer (should use cached PLT)"
echo "5. mix phx.server"
