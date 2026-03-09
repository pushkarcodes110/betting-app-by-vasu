#!/bin/bash

set -euo pipefail

echo "Starting entrypoint script..."

RUN_MIGRATIONS="${RUN_MIGRATIONS:-true}"
WEB_CONCURRENCY="${WEB_CONCURRENCY:-2}"
GUNICORN_THREADS="${GUNICORN_THREADS:-2}"
GUNICORN_TIMEOUT="${GUNICORN_TIMEOUT:-60}"
GUNICORN_KEEPALIVE="${GUNICORN_KEEPALIVE:-2}"
GUNICORN_MAX_REQUESTS="${GUNICORN_MAX_REQUESTS:-500}"
GUNICORN_MAX_REQUESTS_JITTER="${GUNICORN_MAX_REQUESTS_JITTER:-50}"
GUNICORN_ACCESS_LOG="${GUNICORN_ACCESS_LOG:-false}"

if [[ -n "${POSTGRES_HOST:-}" && -n "${POSTGRES_PORT:-}" && -n "${POSTGRES_USER:-}" ]]; then
  echo "Waiting for PostgreSQL..."
  while ! pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER"; do
    echo "PostgreSQL is unavailable - sleeping"
    sleep 2
  done
  echo "PostgreSQL is up - continuing..."
fi

if [[ "$RUN_MIGRATIONS" == "true" || "$RUN_MIGRATIONS" == "1" ]]; then
  echo "Running database migrations..."
  python manage.py migrate --noinput
else
  echo "Skipping migrations (RUN_MIGRATIONS=${RUN_MIGRATIONS})"
fi

# Create superuser only when explicitly configured through env vars
if [[ -n "${DJANGO_SUPERUSER_USERNAME:-}" && -n "${DJANGO_SUPERUSER_EMAIL:-}" && -n "${DJANGO_SUPERUSER_PASSWORD:-}" ]]; then
  echo "Creating superuser if needed..."
  python manage.py shell << END
from django.contrib.auth import get_user_model
User = get_user_model()
username = "$DJANGO_SUPERUSER_USERNAME"
email = "$DJANGO_SUPERUSER_EMAIL"
password = "$DJANGO_SUPERUSER_PASSWORD"
if not User.objects.filter(username=username).exists():
    User.objects.create_superuser(username, email, password)
    print('Superuser created successfully')
else:
    print('Superuser already exists')
END
else
  echo "Skipping superuser creation (DJANGO_SUPERUSER_* vars not set)"
fi

ACCESS_LOG_ARGS=(--access-logfile /dev/null)
if [[ "$GUNICORN_ACCESS_LOG" == "true" || "$GUNICORN_ACCESS_LOG" == "1" ]]; then
  ACCESS_LOG_ARGS=(--access-logfile -)
fi

echo "Starting Gunicorn..."
exec gunicorn mymainserver.wsgi:application \
    --bind 0.0.0.0:8000 \
    --workers "$WEB_CONCURRENCY" \
    --threads "$GUNICORN_THREADS" \
    --timeout "$GUNICORN_TIMEOUT" \
    --keep-alive "$GUNICORN_KEEPALIVE" \
    --max-requests "$GUNICORN_MAX_REQUESTS" \
    --max-requests-jitter "$GUNICORN_MAX_REQUESTS_JITTER" \
    "${ACCESS_LOG_ARGS[@]}" \
    --error-logfile - \
    --log-level info
