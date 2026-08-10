#!/bin/sh

write_certbot_metrics() {
  run_success=$1
  metrics_dir=/var/lib/node_exporter/textfile_collector
  metrics_file="$metrics_dir/certbot.prom"
  certificate_file="/etc/letsencrypt/live/$TLS_CERT_NAME/cert.pem"
  now=$(date +%s)
  last_success=0
  certificate_expiry=0

  mkdir -p "$metrics_dir"

  if [ -f "$metrics_file" ]; then
    last_success=$(awk '$1 == "certbot_renew_last_success_timestamp_seconds" { print $2 }' "$metrics_file")
    last_success=${last_success:-0}
  fi

  if [ "$run_success" -eq 1 ]; then
    last_success=$now
  fi

  if [ -f "$certificate_file" ]; then
    certificate_expiry=$(python3 - "$certificate_file" <<'PY'
import ssl
import sys

certificate = ssl._ssl._test_decode_cert(sys.argv[1])
print(int(ssl.cert_time_to_seconds(certificate["notAfter"])))
PY
)
  fi

  temporary_file=$(mktemp "$metrics_dir/.certbot.prom.XXXXXX")
  cat > "$temporary_file" <<EOF
# HELP certbot_renew_last_run_success Whether the last Certbot issue or renewal command succeeded.
# TYPE certbot_renew_last_run_success gauge
certbot_renew_last_run_success $run_success
# HELP certbot_renew_last_run_timestamp_seconds Unix timestamp of the last Certbot issue or renewal attempt.
# TYPE certbot_renew_last_run_timestamp_seconds gauge
certbot_renew_last_run_timestamp_seconds $now
# HELP certbot_renew_last_success_timestamp_seconds Unix timestamp of the last successful Certbot command.
# TYPE certbot_renew_last_success_timestamp_seconds gauge
certbot_renew_last_success_timestamp_seconds $last_success
# HELP certbot_certificate_expiry_timestamp_seconds Unix timestamp when the managed certificate expires.
# TYPE certbot_certificate_expiry_timestamp_seconds gauge
certbot_certificate_expiry_timestamp_seconds{certificate="$TLS_CERT_NAME"} $certificate_expiry
EOF
  mv "$temporary_file" "$metrics_file"
}
