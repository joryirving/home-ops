#!/usr/bin/env bash
# Validate media pipeline alert rules against unit-test fixtures with promtool.
# Uses a local promtool when present, otherwise runs the cluster's Prometheus image.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 - "$TMP" <<'PY'
import sys, yaml
tmp = sys.argv[1]
for src, out in [
    ("kubernetes/apps/base/observability/exporters/scraparr/prometheusrule.yaml", "rules-scraparr.yaml"),
    ("kubernetes/apps/base/observability/exporters/sabnzbd-exporter/prometheusrule.yaml", "rules-sabnzbd.yaml"),
]:
    doc = yaml.safe_load(open(src))
    yaml.safe_dump({"groups": doc["spec"]["groups"]}, open(f"{tmp}/{out}", "w"))
PY
cp kubernetes/apps/base/observability/exporters/tests/media-alerts.test.yml "$TMP/"

if command -v promtool >/dev/null 2>&1; then
    (cd "$TMP" && promtool check rules rules-scraparr.yaml rules-sabnzbd.yaml && promtool test rules media-alerts.test.yml)
else
    kubectl -n observability delete configmap media-alerts-test --ignore-not-found >/dev/null
    kubectl -n observability create configmap media-alerts-test --from-file="$TMP" >/dev/null
    kubectl -n observability run media-alerts-test --restart=Never \
        --image=mirror.gcr.io/prom/prometheus:v3.5.0 \
        --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65534,"fsGroup":65534,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"media-alerts-test","image":"mirror.gcr.io/prom/prometheus:v3.5.0","command":["sh","-c","cd /cfg && promtool check rules rules-scraparr.yaml rules-sabnzbd.yaml && promtool test rules media-alerts.test.yml"],"volumeMounts":[{"name":"cfg","mountPath":"/cfg"}]}],"volumes":[{"name":"cfg","configMap":{"name":"media-alerts-test"}}]}}' >/dev/null
    status=$(kubectl -n observability wait --for=condition=Ready pod/media-alerts-test --timeout=180s >/dev/null 2>&1; \
             kubectl -n observability wait pod/media-alerts-test --for=jsonpath='{.status.phase}'=Succeeded --timeout=180s >/dev/null 2>&1; \
             kubectl -n observability get pod media-alerts-test -o jsonpath='{.status.phase}')
    kubectl -n observability logs media-alerts-test || true
    kubectl -n observability delete pod media-alerts-test configmap media-alerts-test --ignore-not-found >/dev/null
    [ "$status" = "Succeeded" ]
fi
