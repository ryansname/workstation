#! /bin/bash

./deps.sh
nix-shell --run 'zig build --summary all'
