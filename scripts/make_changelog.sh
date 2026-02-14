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
read -p "Future release is v${VER}. Please press any key to confirm..."

export GITHUB_TOKEN=$(gh auth token)

git-cliff --tag "v${VER}" -o CHANGELOG.md
