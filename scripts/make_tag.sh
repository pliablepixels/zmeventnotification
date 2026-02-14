#!/bin/bash
if [ -z "$1" ]; then
    echo 'Getting version from VERSION file'
    if [ ! -f ./VERSION ]; then
	    echo "VERSION file not found"
	    exit 1
    fi
    TAGVER=$(cat ./VERSION | tr -d '[:space:]')
else
	TAGVER=$1
fi
VER="${TAGVER/v/}"
echo "Creating tag:v$VER"
echo
read -p "Please generate CHANGELOG and commit it BEFORE you tag. Press a key when ready..."
read -p "Press any key to create the tag or Ctrl-C to break..." -n1

git tag -fa v$VER -m"v$VER"
git push origin -f --tags