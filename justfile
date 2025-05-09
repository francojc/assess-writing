#!/usr/bin/env just

# This justfile helps segment natural groupings of commands

get-materials:
  pull.sh; acquire.sh;
