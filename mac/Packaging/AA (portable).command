#!/bin/sh
# Start AA with its data in the "AA Data" folder beside this file (portable use, e.g. on a USB stick).
here="$(cd "$(dirname "$0")" && pwd -P)"
exec /usr/bin/open -n -a "$here/AA.app" --args --data-dir "$here/AA Data"
