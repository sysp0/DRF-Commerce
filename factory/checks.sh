#!/usr/bin/env bash
# The repo's checks. Exit 0 only when the branch is fit to review.
#
# The gate runs this script from the main checkout with the job's worktree as
# the working directory. Keep it fast, deterministic and non-interactive: no
# watch modes, no prompts, nothing that rewrites files.
#
# Everything runs on config.django.test (SQLite, in-memory cache, eager Celery),
# so no Postgres, Redis or RabbitMQ is needed.
set -euo pipefail

export DJANGO_SETTINGS_MODULE=config.django.test
base="origin/$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["base_branch"])' \
  "$(dirname "$0")/config.json")"

# Dependencies from uv.lock, dev group included. --locked fails if pyproject.toml
# changed without `uv lock`.
uv sync --locked --quiet

# Settings, URLconf and models load, and every model change has a migration.
uv run --no-sync python manage.py check
uv run --no-sync python manage.py makemigrations --check --dry-run

# Lint. Syntax errors and undefined names fail anywhere. The existing code has
# style and typing debt, so only Python files this branch adds must pass flake8
# in full, and the non-test ones mypy too (pyproject sets disallow_untyped_defs).
uv run --no-sync flake8 . --exclude .git,.venv,__pycache__,'*/migrations/*' --select E9,F63,F7,F82
added=$(git diff --name-only --diff-filter=A "$base...HEAD" -- '*.py' ':(exclude)*/migrations/*')
if [ -n "$added" ]; then
  mapfile -t added <<< "$added"
  uv run --no-sync flake8 --max-line-length 120 "${added[@]}"
  typed=()
  for f in "${added[@]}"; do
    case "$f" in
      */tests/*|*/test_*.py|*/tests.py|*_tests.py|*conftest.py) ;;
      *) typed+=("$f") ;;
    esac
  done
  if [ ${#typed[@]} -gt 0 ]; then
    uv run --no-sync mypy --follow-imports=silent "${typed[@]}"
  fi
fi

# Tests. Exit 5 means pytest collected no tests, which is fine until the
# suite has some.
uv run --no-sync pytest -q -p no:cacheprovider || test $? -eq 5
