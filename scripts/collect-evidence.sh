#!/usr/bin/env bash
# Guarda en docs/evidencias/ la salida de los comandos que demuestran el despliegue.
# Uso: ./scripts/collect-evidence.sh   (con kubectl apuntando al cluster)
set -euo pipefail

OUT="docs/evidencias"
mkdir -p "$OUT"
TS=$(date +%Y%m%d-%H%M%S)

run() {
  local name="$1"; shift
  { echo "\$ $*"; "$@"; } > "$OUT/${TS}-${name}.txt" 2>&1 || true
  echo "guardado: $OUT/${TS}-${name}.txt"
}

run nodes          kubectl get nodes -o wide
run app-resources  kubectl -n pf-devops get pods,svc,ingress,hpa,pdb -o wide
run rollout        kubectl -n pf-devops rollout status deployment/pf-devops-app
run top-pods       kubectl -n pf-devops top pods
run monitoring     kubectl -n monitoring get pods
run servicemonitor kubectl -n pf-devops get servicemonitor,prometheusrule
run app-logs       kubectl -n pf-devops logs deployment/pf-devops-app --tail=50
run hpa-describe   kubectl -n pf-devops describe hpa pf-devops-app

echo
echo "Ahora agregá a mano capturas de: ejecuciones de GitHub Actions, dashboard de Grafana,"
echo "targets de Prometheus y el reporte de ZAP (artifact zap-report)."
