#!/bin/bash
set -e
cd WebApp/src

if [ "$RAILWAY_SERVICE_NAME" = "Athlynk" ]; then
  python manage.py collectstatic --noinput
  python manage.py migrate --noinput
  exec gunicorn config.wsgi:application --bind 0.0.0.0:$PORT --workers 2 --worker-class gthread --threads 4 --timeout 60
elif [ "$RAILWAY_SERVICE_NAME" = "Analytics_Cron" ]; then
  python manage.py run_daily_analytics
else
  echo "ERROR: unknown RAILWAY_SERVICE_NAME='$RAILWAY_SERVICE_NAME'" >&2
  exit 1
fi
