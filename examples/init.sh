#!/bin/sh
# Example --init-script payload. Runs as root inside the container, before the
# agent is attached to your terminal.
apk update
apk add curl
