#!/bin/bash
# Do not remove nor edit this file unless necessary.
exec /usr/bin/rg "${@/--cursor-ignore/--ignore-file}"
