#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: ./new-project.sh <project-name>"
  exit 1
fi

PROJECT=$1

mkdir -p $PROJECT/{docs,configs,scripts,screenshots}

touch $PROJECT/README.md \
      $PROJECT/docs/setup.md \
      $PROJECT/docs/walkthrough.md \
      $PROJECT/docs/lessons.md

echo "✅ Created: $PROJECT"
echo "📁 Structure:"
find $PROJECT -type f | sort

# chmod +x project.sh      
# ./project.sh project-name