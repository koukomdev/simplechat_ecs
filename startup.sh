#!/usr/bin/env bash

mysql -h ${DB_HOST} -u ${DB_USER} -p${DB_PASS} < /schema.sql
bundle exec ruby /app/myapp.rb -o 0.0.0.0 -e production
