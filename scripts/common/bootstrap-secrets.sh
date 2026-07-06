#!/bin/bash
# Bootstrap the out-of-band Secrets this repo deliberately keeps out of git
# (see CLAUDE.md "Secrets"). Everything else deploys from Git via Flux, so a
# fresh cluster is: k3s install -> flux bootstrap -> this script.
#
# Idempotent: re-run any time to rotate either secret (pods are restarted so
# the new values take effect immediately).
set -euo pipefail

kubectl get namespace monitoring >/dev/null 2>&1 || kubectl create namespace monitoring

# 1. Grafana admin credentials (random password, printed once)
GRAFANA_PASSWORD=$(openssl rand -base64 15)
kubectl create secret generic grafana-admin-credentials \
  --namespace monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$GRAFANA_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n monitoring delete pod -l app.kubernetes.io/name=grafana --ignore-not-found >/dev/null
echo "grafana-admin-credentials applied. Password (shown once, store it now): $GRAFANA_PASSWORD"

# 2. Telegram bot token for Alertmanager -> Telegram alert delivery
read -rsp "Telegram bot token from @BotFather (empty to skip): " TELEGRAM_TOKEN; echo
if [ -n "$TELEGRAM_TOKEN" ]; then
  kubectl create secret generic alertmanager-telegram \
    --namespace monitoring \
    --from-literal=token="$TELEGRAM_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n monitoring delete pod -l app.kubernetes.io/name=alertmanager --ignore-not-found >/dev/null
  echo "alertmanager-telegram applied."
else
  echo "WARNING: skipped alertmanager-telegram — the Alertmanager pod cannot start"
  echo "without it (mounted via alertmanagerSpec.secrets). Re-run this script to add it."
fi

echo
echo "Reminder: TELEGRAM_CHAT_ID is config, not a secret — it lives in"
echo "clusters/homelab/cluster-config.yaml."
