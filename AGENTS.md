# AGENTS.md

Instructions for anyone, human or agent, changing this repo.

## The project

DRF-Commerce is an online shop backend built to show real skills in Django,
Django REST Framework and DevOps. It is an API only; there is no frontend in
this repo.

- Django 5.2, DRF 3.16, SimpleJWT for auth, drf-spectacular for the OpenAPI
  schema, django-filter.
- Postgres, Redis (cache), Celery with RabbitMQ, celery-beat and
  celery-results.
- Python `>=3.10` (`.python-version` pins 3.12), dependencies managed with
  [uv](https://docs.astral.sh/uv/) in `pyproject.toml` and `uv.lock`.

## Layout

```
config/
  django/base.py         settings shared by every environment
  django/local.py        manage.py default: eager Celery
  django/test.py         pytest: SQLite, in-memory cache, eager Celery
  django/production.py   secrets and hosts from the environment
  settings/*.py          per-feature settings (cors, jwt, celery, ...), imported at the end of base.py
  env.py                 `env` (django-environ) and BASE_DIR
  urls.py                /schema/, Swagger at /, /redoc/, /admin/, /api/
drf_commerce/
  api/                   /api/ URLconf, ApiAuthMixin, pagination, exception handlers
  common/                BaseModel (created_at, updated_at), model_update, get_object
  core/exceptions.py     ApplicationError
  users/                 BaseUser (custom user, email login), Profile, register and profile APIs
  authentication/        SimpleJWT login, refresh and verify URLs
  tasks/                 the Celery app and setup_periodic_tasks
  utils/tests/base.py    a shared Faker instance for tests
```

Each app's URLs are included from `drf_commerce/api/urls.py`. That list is
empty today, so `users/urls.py` and `authentication/urls.py` aren't routed yet.

## Conventions

The code follows the HackSoft Django Styleguide:

- **Models** inherit `drf_commerce.common.models.BaseModel`. Constraints and
  validation live on the model; call `full_clean()` before saving.
- **Services** (`services.py`) do every write. Keyword-only arguments, type
  hints, `@transaction.atomic` when they write more than one row, and
  `model_update` for updates.
- **Selectors** (`selectors.py`) do reads and filter by the caller where data
  belongs to a user.
- **APIs** (`apis.py`) are thin `APIView`s with nested input and output
  serializers, documented with `@extend_schema`. They validate input, call a
  service or selector, and serialize the result. Lists use
  `drf_commerce.api.pagination.LimitOffsetPagination`.
- **Auth**: `REST_FRAMEWORK` sets no default authentication or permission
  classes, so a view is public unless it uses `ApiAuthMixin`
  (`drf_commerce/api/mixins.py`). Use it on every endpoint that isn't meant to
  be public.
- **Errors**: raise `ApplicationError` or Django's `ValidationError` from
  services; `drf_default_with_modifications_exception_handler` turns them into
  DRF responses shaped `{"detail": ...}`.
- **Money** is `DecimalField`, never float, and is computed on the server.
- **New apps** go in `drf_commerce/<app>/` and are added to `LOCAL_APPS` in
  `config/django/base.py`.
- **Settings and secrets** come from the environment through `config.env.env`;
  never commit a secret or a `.env` file.
- **Migrations**: generate them with `makemigrations`; never edit or delete one
  that is already on `main`.
- **Types**: new modules are fully typed (mypy with django-stubs, configured in
  `pyproject.toml`). Older modules still have typing and flake8 debt; don't
  fix it in unrelated changes.
- **Tests** use pytest with pytest-django, `@pytest.mark.django_db`,
  factory-boy and Faker. Put them in `drf_commerce/<app>/tests/test_<module>.py`
  (with an `__init__.py`), and add a new file rather than editing an existing
  test.
- **Commits**: one line, in the style of `git log --oneline`
  (gitmoji, then `type(Scope): Summary`).

## Setup

```bash
uv sync --locked          # creates .venv with the dev dependencies
```

Nothing else is needed for the tests or the dev server below. For the full
stack, `cp env.example .env`, fill it in, and start Postgres, RabbitMQ and
Redis with `docker compose -f docker-compose.dev.yml up -d` (host ports 54321,
56721 and 63791).

## Dev server

On a throwaway SQLite database in the checkout (`db.sqlite3` is gitignored),
on any port:

```bash
export DATABASE_URL=sqlite:///db.sqlite3
uv run python manage.py migrate
uv run python manage.py runserver 127.0.0.1:<port>
```

Swagger is at `/`, Redoc at `/redoc/`, the schema at `/schema/` and the admin at
`/admin/`. For an admin login on that database:
`DJANGO_SUPERUSER_PASSWORD=<pw> uv run python manage.py createsuperuser --noinput --email admin@example.com`.

## Validation

`bash factory/checks.sh` runs everything below and exits non-zero on any
failure. All of it uses `config.django.test`, so no services are needed.

```bash
uv sync --locked
DJANGO_SETTINGS_MODULE=config.django.test uv run python manage.py check
DJANGO_SETTINGS_MODULE=config.django.test uv run python manage.py makemigrations --check --dry-run
uv run flake8 . --exclude .git,.venv,__pycache__,'*/migrations/*' --select E9,F63,F7,F82
uv run flake8 --max-line-length 120 <new .py files>
uv run mypy --follow-imports=silent <new non-test .py files>
uv run pytest
```

## Review hot spots

What reviewers and the approver should look at hardest in this repo.

- **Access**: a DRF view without `ApiAuthMixin` (or its own permission
  classes) is public. Selectors filter by `request.user` for anything a user
  owns: carts, orders, addresses, profiles. Staff-only actions check
  `is_admin`. Nothing lets a caller set `is_admin`, `is_superuser`,
  `is_active` or another user's email.
- **Identity**: `BaseUser` and its manager (`drf_commerce/users/models.py`),
  registration and password validators (`drf_commerce/users/apis.py`,
  `validators.py`), the JWT views and settings
  (`drf_commerce/authentication/urls.py`, `config/settings/jwt.py`).
- **Money and stock**: prices and totals come from the database, never the
  request. Stock and order state change inside a transaction with
  `select_for_update` or `F()`, so two requests can't oversell. Payment
  webhooks verify the signature and are idempotent.
- **Data exposure**: output serializers list their fields (no `"__all__"` on
  `BaseUser`), and errors don't echo exceptions to the caller.
- **Who uses it**: shoppers through a frontend or mobile app (anonymous and
  signed in), frontend developers reading Swagger at `/`, and staff in the
  Django admin at `/admin/`. The only pages are the admin, Swagger and Redoc;
  they use stock Django and drf-spectacular styling.
- **Always for a human**: changes to auth, permissions, prices, payments or
  order state; any migration; settings in `config/`, `Procfile`, `docker/` or
  `docker-compose*.yml`; new dependencies; a new public endpoint, or a removed
  or renamed field clients already use.

## Software factory

`/factory run` builds every open GitHub issue labeled `factory` through
intake → spec → build → gate → review → approve, one PR per issue. State is in
`factory/jobs/` (gitignored); `factory/bin/job` is its only writer. Checks:
`factory/checks.sh`. Dashboard: `cd factory && python3 -m http.server`, then
open http://localhost:8000/dashboard.html.

The factory (`.claude/` and `factory/`) is adapted from ZazenCodes'
[software-factory-claude-code-v2](https://github.com/zazencodes/zazencodes-season-3/tree/main/src/software-factory-claude-code-v2),
which is GPLv3; see `factory/LICENSE`.
