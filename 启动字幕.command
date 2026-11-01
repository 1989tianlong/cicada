#!/bin/bash
# Opens the installed app, or the one built in this checkout.
cd "$(dirname "$0")"
if [ -d "/Applications/LiveSubs.app" ]; then open "/Applications/LiveSubs.app"; else open "build/LiveSubs.app"; fi
