#!/usr/bin/env bash
# Show container health for Sentry and the proxy.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dc ps --format 'table {{.Service}}\t{{.Status}}'
echo
dc_proxy ps --format 'table {{.Service}}\t{{.Status}}'
