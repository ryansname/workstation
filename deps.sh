#!/bin/bash

mkdir -p libs
cd libs

[ ! -d zig-imgui ] && git clone https://github.com/SpexGuy/Zig-ImGui.git
(cd zig-imgui && git fetch && git checkout 0a2cfca)

