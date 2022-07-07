#!/bin/bash

mkdir -p libs
cd libs

[ ! -d mach-glfw ] && git clone https://github.com/hexops/mach-glfw.git
(cd mach-glfw && git fetch && git checkout 385f718)
