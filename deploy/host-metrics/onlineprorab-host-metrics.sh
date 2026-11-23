#!/usr/bin/env bash
# Publishes root-disk and memory usage of the API host to CloudWatch every run
# (see onlineprorab-host-metrics.timer). The alarms live in
# deploy/aws/onlineprorab-storage.yaml (HostDiskFull, HostMemoryLow,
# HostMetricsMissing); the instance role needs HostMetricsWriterPolicy.
set -Eeuo pipefail

environment="${ONLINEPRORAB_ENVIRONMENT:-production}"
region="${AWS_REGION:-eu-north-1}"
if [[ ! "$environment" =~ ^(staging|production)$ ]]; then
  echo "ONLINEPRORAB_ENVIRONMENT must be staging or production" >&2
  exit 2
fi

disk_used_percent="$(df --output=pcent / | tail -n 1 | tr -dc '0-9')"
mem_total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
mem_available_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
if [[ -z "$disk_used_percent" || -z "$mem_total_kb" || -z "$mem_available_kb" || "$mem_total_kb" -eq 0 ]]; then
  echo "could not read disk or memory usage" >&2
  exit 1
fi
mem_available_percent="$(awk -v a="$mem_available_kb" -v t="$mem_total_kb" 'BEGIN {printf "%.1f", a * 100 / t}')"

aws cloudwatch put-metric-data \
  --region "$region" \
  --namespace "OnlineProrab/Host/$environment" \
  --metric-data \
    "MetricName=DiskUsedPercent,Dimensions=[{Name=Environment,Value=$environment}],Value=$disk_used_percent,Unit=Percent" \
    "MetricName=MemoryAvailablePercent,Dimensions=[{Name=Environment,Value=$environment}],Value=$mem_available_percent,Unit=Percent"
