#!/bin/bash
~/bin/godot4 --headless --path "$(dirname "$(realpath "$0")")/.." -s scripts/print_tech_tree.gd
