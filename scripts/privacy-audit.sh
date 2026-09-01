#!/bin/bash

set -u

failure=0

report_failure() {
    printf 'Privacy audit failed: %s\n' "$1" >&2
    failure=1
}

is_public_commit_email() {
    case "$1" in
        *@users.noreply.github.com|noreply@github.com|checkpointer@noreply)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# A full checkout is required so content that was added and then deleted in a
# later commit cannot bypass the audit.
if [ "$#" -gt 0 ]; then
    public_commits=$(git rev-list "$@" | sort -u)
else
    public_commits=$(git rev-list HEAD --branches --remotes --tags | sort -u)
fi
commit_count=$(printf '%s\n' "$public_commits" | grep -c .)
if [ "$commit_count" -eq 0 ]; then
    report_failure "no reachable commits were found"
fi

for commit in $public_commits; do
    metadata=$(git show -s --format='%ae|%ce' "$commit")
    author_email=${metadata%%|*}
    committer_email=${metadata#*|}
    if ! is_public_commit_email "$author_email"; then
        report_failure "commit ${commit} uses a non-public author email"
    fi
    if ! is_public_commit_email "$committer_email"; then
        report_failure "commit ${commit} uses a non-public committer email"
    fi

    if git grep -n -I -E '/Users/[A-Za-z0-9._-]+/' "$commit" -- . 2>/dev/null \
        | grep -qv '/Users/Shared/'; then
        report_failure "commit ${commit} contains a personal macOS home path"
    fi

    if git grep -q -I -E \
        '[A-Za-z0-9._%+-]+@(gmail|hotmail|outlook|icloud)\.com' \
        "$commit" -- . 2>/dev/null; then
        report_failure "commit ${commit} contains a personal email address"
    fi

    if git grep -q -I -E \
        'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}' \
        "$commit" -- . 2>/dev/null; then
        report_failure "commit ${commit} contains a credential-like value"
    fi

    if git ls-tree -r --name-only "$commit" \
        | grep -qE '(^|/)(\.env($|\.)|id_(rsa|ed25519)($|\.)|[^/]+\.(pem|p12|pfx|key)$|credentials?($|\.)|secrets?($|\.))'; then
        report_failure "commit ${commit} contains a sensitive filename"
    fi

    if git ls-tree -r --name-only "$commit" \
        | grep -qE '(^|/)(dist|dist-bundled|DerivedData|\.build)(/|$)|\.app/|\.dmg$'; then
        report_failure "commit ${commit} contains a generated build artifact"
    fi
done

if [ "$failure" -ne 0 ]; then
    exit 1
fi

printf 'Privacy audit passed for %s reachable commits.\n' "$commit_count"
