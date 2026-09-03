#!/bin/bash

set -u

failure=0

report_failure() {
    printf 'Interoperability audit failed: %s\n' "$1" >&2
    failure=1
}

# The current product must remain a native client. Historical documentation is
# intentionally excluded so it can accurately describe the retired design.
for forbidden_path in bridge.py setup.sh; do
    if [ -e "$forbidden_path" ]; then
        report_failure "retired runtime file is tracked: $forbidden_path"
    fi
done

while IFS= read -r tracked_path; do
    if [ -e "$tracked_path" ] \
        && printf '%s\n' "$tracked_path" \
        | grep -qE '(^|/)(antelope_modules|python-runtime)(/|$)|\.py[co]$'; then
        report_failure "extracted module or Python runtime content is tracked"
        break
    fi
done < <(git ls-files)

if git grep -n -I -E \
    'SourcelessFileLoader|marshal\.loads|PyInstaller|report_format_[A-Za-z0-9_]*\.json' \
    -- Sources Config build-dist.sh Package.swift project.yml 2>/dev/null; then
    report_failure "retired extraction or bytecode-loading logic is present"
fi

if [ "$failure" -ne 0 ]; then
    exit 1
fi

printf 'Native interoperability boundary audit passed.\n'
