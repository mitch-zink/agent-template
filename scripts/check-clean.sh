#!/usr/bin/env bash
# Fails if the template contains anything that looks personal or secret.
# ponytail: regex scan, misses names; the export-template skill covers those.
cd "$(dirname "$0")/.." || exit 1
pat='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.(com|net|org|io|dev|co|sh|ai|app)\b|\(?\b[0-9]{3}\)?[-. ][0-9]{3}[-. ][0-9]{4}\b|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{20,}\.'
allow='noreply@|@example\.com|sender@example|you@'
# Only files git would publish: tracked + untracked-not-ignored. Ignored .env and node_modules are out of scope.
hits=$(git ls-files -z -co --exclude-standard -- . ':!scripts/check-clean.sh' ':!**/package-lock.json' | xargs -0 grep -EnH "$pat" 2>/dev/null | grep -Ev "$allow")
[ -z "$hits" ] && { echo "clean"; exit 0; }
echo "$hits"; exit 1
