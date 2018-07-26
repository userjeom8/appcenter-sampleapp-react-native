#!/bin/bash

brew update
set +u
echo "Homebrew cache directory: $(brew --cache), Homebrew domain: ${HOMEBREW_BOTTLE_DOMAIN}"
set -u
brew install imagemagick librsvg
