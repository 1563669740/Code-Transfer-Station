#!/usr/bin/env bash

SERVER_TIMEZONE="${SERVER_TIMEZONE:-Asia/Shanghai}"
export TZ="$SERVER_TIMEZONE"

server_date() {
  TZ="$SERVER_TIMEZONE" date "$@"
}

server_timestamp() {
  server_date '+%Y-%m-%d %H:%M:%S %z'
}

server_log_stamp() {
  server_date '+%Y%m%d_%H%M%S'
}
