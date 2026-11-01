#!/bin/bash
# Opens the installed app, or the one built in this checkout.
cd "$(dirname "$0")"
if [ -d "/Applications/Cicada.app" ]; then open "/Applications/Cicada.app"; else open "build/Cicada.app"; fi
