#!/bin/sh

set -xe

gnatmake -Wall -Wextra game.adb -largs -L./raylib/raylib-5.0_linux_amd64/lib/ -l:libraylib.a -lm
./game

# gnatmake -gnat2022 test.adb
# ./test
