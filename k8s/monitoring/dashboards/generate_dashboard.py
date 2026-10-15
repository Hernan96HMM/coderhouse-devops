import json

DS = {"type": "prometheus", "uid": "${DS_PROMETHEUS}"}


def panel(pid, title, expr, x, y, unit="short", legend="{{pod}}", w=12, h=8):
    return {
        "id": pid,
        "type": "timeseries",
        "title": title,
        "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "fieldConfig": {"defaults": {"unit": unit}, "overrides": []},
        "targets": [{"datasource": DS, "expr": expr, "legendFormat": legend, "refId": "A"}],
    }


NS = 'namespace="pf-devops"'
panels = [
    panel(1, "Requests por segundo", 'sum(rate(http_requests_total[1m])) by (route)', 0, 0, "reqps", "{{route}}"),
    panel(2, "Latencia p95", 'histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[1m])) by (le))', 12, 0, "s", "p95"),
    panel(3, "CPU por pod", f'sum(rate(container_cpu_usage_seconds_total{{{NS},container="app"}}[1m])) by (pod)', 0, 8, "none"),
    panel(4, "Memoria por pod", f'sum(container_memory_working_set_bytes{{{NS},container="app"}}) by (pod)', 12, 8, "bytes"),
    panel(5, "Réplicas del HPA (actuales vs deseadas)",
          f'kube_horizontalpodautoscaler_status_current_replicas{{{NS}}}', 0, 16, "short", "actuales"),
    panel(6, "Errores 5xx por segundo", 'sum(rate(http_requests_total{status=~"5.."}[1m]))', 12, 16, "reqps", "5xx"),
]
panels[4]["targets"].append({
    "datasource": DS,
    "expr": f'kube_horizontalpodautoscaler_status_desired_replicas{{{NS}}}',
    "legendFormat": "deseadas",
    "refId": "B",
})

dashboard = {
    "uid": "pf-devops-app",
    "title": "PF DevOps - Aplicación",
    "tags": ["pf-devops"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 1,
    "refresh": "10s",
    "time": {"from": "now-30m", "to": "now"},
    "templating": {
        "list": [
            {
                "name": "DS_PROMETHEUS",
                "type": "datasource",
                "query": "prometheus",
                "label": "Datasource",
            }
        ]
    },
    "panels": panels,
}

with open("pf-devops.json", "w") as f:
    json.dump(dashboard, f, indent=2, ensure_ascii=False)
print("ok")
