#!/usr/bin/env bash
# Create a Sentry superuser. Prompts for the password.
# Usage: scripts/create-admin.sh admin@company.com
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

email=${1:?usage: $0 <email>}
dc run --rm web createuser --superuser --email "$email"
