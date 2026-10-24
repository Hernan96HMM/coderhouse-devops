# PF DevOps – Pipeline CI/CD, IaC y Kubernetes en AWS

Proyecto final: una API Node.js desplegada de punta a punta con **Docker multi-stage, Terraform (VPC + EKS), GitHub Actions, Kubernetes (Deployment, Service, Ingress, HPA), Prometheus + Grafana, SAST/DAST y prácticas de FinOps**.

## Arquitectura

```
git push ─► GitHub Actions
             ├─ CI:  tests ─► SAST (CodeQL, Trivy IaC) ─► build ─► Trivy imagen ─► push GHCR
             ├─ Infra: terraform fmt/validate/plan/apply (OIDC, sin claves largas)
             └─ CD:  helm (metrics-server, ingress-nginx, kube-prometheus-stack)
                      ─► kubectl apply -k k8s/base ─► smoke test ─► DAST (OWASP ZAP)

AWS: VPC (subnets públicas/privadas) ─► EKS (node group spot) ─► ingress-nginx (NLB) ─► Service ─► Pods (HPA 2–8)
Monitoreo: ServiceMonitor ─► Prometheus ─► Grafana (dashboard "PF DevOps - Aplicación")
```

## Estructura del repositorio

| Ruta | Contenido |
|---|---|
| `app/` | API Express (`/`, `/health`, `/metrics`, `/api/sum`, `/api/load`), tests y `Dockerfile` multi-stage |
| `terraform/` | Raíz con variables, módulos `network`, `cluster`, `finops`, tfvars por entorno (`envs/`) y `bootstrap/` (estado remoto + OIDC) |
| `k8s/base/` | Namespace, Deployment, Service, Ingress, HPA, PDB (kustomize) |
| `k8s/overlays/local/` | Variante para cluster local con kind |
| `k8s/monitoring/` | Values de kube-prometheus-stack, ServiceMonitor, alertas, dashboard de Grafana |
| `.github/workflows/` | `ci.yml`, `infra.yml`, `cd.yml`, `finops.yml` |
| `scripts/` | Config de kind y script para juntar evidencias |
| `docs/` | Informe y evidencias |

## Requisitos

- Docker, Node.js 20+, Git
- Para pruebas locales de Kubernetes: `kind`, `kubectl`, `helm`
- Para el entorno en AWS: cuenta AWS, AWS CLI, Terraform >= 1.6
- Cuenta de GitHub (Actions + GHCR)

## 1. Ejecutar localmente

### 1.1 Solo la app

```bash
cd app
npm install
npm test
npm start                      # http://localhost:3000
curl localhost:3000/health
curl "localhost:3000/api/sum?a=2&b=3"
curl localhost:3000/metrics | head
```

### 1.2 Con Docker

```bash
docker build -t pf-devops-app:local ./app     # ejecuta los tests dentro del build
docker run --rm -p 3000:3000 pf-devops-app:local
```

### 1.3 En Kubernetes local (kind) — entorno de pruebas sin costo

```bash
kind create cluster --name pf --config scripts/kind-config.yaml --image kindest/node:v1.34.0
# Nota: fijar la imagen del nodo es necesario si Docker usa cgroup v1 (docker info | findstr Cgroup);
# la versión por defecto de kind (K8s 1.37) ya no arranca en cgroup v1.
docker build -t pf-devops-app:local ./app
kind load docker-image pf-devops-app:local --name pf

# Ingress controller (variante para kind) y metrics-server (necesario para el HPA)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system \
  --set 'args={--kubelet-insecure-tls}'

kubectl wait -n ingress-nginx --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=120s
kubectl apply -k k8s/overlays/local
kubectl -n pf-devops rollout status deployment/pf-devops-app

curl localhost:8080/health          # a través del Ingress
```

Monitoreo local (opcional):

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring --create-namespace \
  -f k8s/monitoring/kube-prometheus-stack-values.yaml --set-string grafana.adminPassword='<elegí-una>'
kubectl apply -k k8s/monitoring
```

## 2. Entorno de pruebas en AWS (EKS)

> **Costos:** EKS cobra el control plane (~US$0,10/h) y cada NAT Gateway (~US$0,045/h) más los nodos y el balanceador. Un entorno `dev` encendido todo el mes ronda los US$100+. **Destruilo cuando termines** (paso 2.6). Revisá precios actuales en la calculadora de AWS.

### 2.1 Bootstrap (una sola vez, a mano)

Crea el bucket/tabla del estado remoto y el rol IAM que asumirá GitHub Actions por OIDC:

```bash
cd terraform/bootstrap
terraform init
terraform apply -var github_repo="<usuario>/<repo>" -var state_bucket_name="<nombre-unico-global>"
```

Guardá los outputs (`state_bucket`, `lock_table`, `github_actions_role_arn`).

### 2.2 Configurar GitHub

En *Settings → Secrets and variables → Actions*:

| Tipo | Nombre | Valor |
|---|---|---|
| Secret | `AWS_ROLE_ARN` | output `github_actions_role_arn` |
| Secret | `GRAFANA_ADMIN_PASSWORD` | contraseña a elección (no se guarda en el repo) |
| Variable | `AWS_REGION` | p. ej. `us-east-1` |
| Variable | `TF_STATE_BUCKET` | output `state_bucket` |
| Variable | `TF_LOCK_TABLE` | output `lock_table` |
| Variable | `CLUSTER_NAME` | `pf-devops-dev` |

Creá los *Environments* `dev` y `prod` (en `prod` podés exigir aprobación manual).

### 2.3 Provisionar la infraestructura

*Actions → Infra (Terraform) → Run workflow* con `environment=dev`, `action=plan` y luego `action=apply`. Revisá el plan antes de aplicar. Antes, editá `terraform/envs/dev.tfvars` y restringí `cluster_public_access_cidrs` a tu IP.

Alternativa manual:

```bash
cd terraform
terraform init -backend-config="bucket=<BUCKET>" -backend-config="key=pf-devops/dev/terraform.tfstate" \
  -backend-config="region=us-east-1" -backend-config="dynamodb_table=<LOCK_TABLE>"
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
$(terraform output -raw kubeconfig_command)
```

### 2.4 Imagen y despliegue

1. Un push a `main` que toque `app/**` dispara **CI**: tests → SAST → build → Trivy → push a `ghcr.io/<owner>/pf-devops-app:<sha>`.
2. Cuando CI termina bien, **CD** instala metrics-server, ingress-nginx y kube-prometheus-stack, aplica `k8s/base`, espera el rollout, aplica el monitoreo y corre un smoke test y **ZAP**.
3. Hacé el paquete de GHCR **público** (*Packages → pf-devops-app → Package settings*), o creá un `imagePullSecret`; si no, los pods quedarán en `ImagePullBackOff`.

### 2.5 Validar el despliegue

```bash
kubectl -n pf-devops get pods,svc,ingress,hpa
kubectl -n pf-devops rollout status deployment/pf-devops-app
URL=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}')
curl $URL/health
```

**Probar el auto-escalado (HPA):**

```bash
# terminal 1
kubectl -n pf-devops get hpa -w
# terminal 2: generar carga de CPU
for i in $(seq 1 200); do curl -s "$URL/api/load?ms=500" >/dev/null & done; wait
```

Debería verse subir `REPLICAS` por encima de 2 y volver a bajar a los pocos minutos.

**Validar monitoreo:**

```bash
kubectl -n monitoring port-forward svc/kps-grafana 3001:80          # http://localhost:3001  (usuario: admin)
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090   # Status → Targets
```

En Prometheus, el target `pf-devops/pf-devops-app` debe figurar *UP*. En Grafana abrí el dashboard **PF DevOps - Aplicación** (requests/s, latencia p95, CPU, memoria, réplicas del HPA, errores 5xx).

### 2.6 Apagar y destruir

```bash
# Apagado temporal (conserva todo, solo se detienen los nodos)
# Actions → FinOps → Run workflow → scale-down
# Destrucción total
# Actions → Infra (Terraform) → environment=dev, action=destroy
```

## 3. Seguridad

- **Secretos:** nada sensible en el repo. Credenciales de AWS por **OIDC** (sin claves de larga duración); contraseña de Grafana y ARN del rol en *GitHub Secrets*; `.gitignore` excluye `*.tfstate`, `.env`, kubeconfig.
- **Contenedor:** imagen Alpine mínima, multi-stage, usuario no root (UID 10001), filesystem de solo lectura, sin capabilities, `seccompProfile: RuntimeDefault`.
- **SAST:** CodeQL (código JS) y Trivy `config` (Terraform + manifiestos K8s); `npm audit` en CI. *Nota:* CodeQL en repos privados requiere GitHub Advanced Security.
- **Imagen:** Trivy bloquea el pipeline si hay vulnerabilidades CRÍTICAS con fix disponible.
- **DAST:** OWASP ZAP baseline contra la URL desplegada; el reporte queda como artifact `zap-report`.
- **Terraform:** estado remoto cifrado y con lock; endpoint público del API restringible por CIDR.
- **Pendiente para producción real:** reemplazar `AdministratorAccess` del rol de CI por mínimo privilegio, TLS en el Ingress (cert-manager) y NetworkPolicies.

## 4. FinOps

| Medida | Dónde |
|---|---|
| Nodos **spot** en dev | `terraform/envs/dev.tfvars` (`node_capacity_type`) |
| Un solo NAT Gateway en dev | `single_nat_gateway = true` |
| **Apagado nocturno** de nodos (22:00–08:00 ART, lun–vie) | módulo `finops` (`aws_autoscaling_schedule`) y/o workflow `finops.yml` |
| **HPA** 2–8 réplicas por CPU/memoria | `k8s/base/hpa.yaml` |
| Requests/limits ajustados (mejor empaquetado) | `k8s/base/deployment.yaml` |
| Retención de métricas de 3 días, Alertmanager apagado | `kube-prometheus-stack-values.yaml` |
| **Tags** de costo (`Project`, `Environment`, `CostCenter`) en todos los recursos | `default_tags` en `terraform/main.tf` |
| **Presupuesto mensual** con alertas al 80 % y 100 % | `terraform/modules/finops` (`budget_alert_emails`) |

> Para activar las alertas de presupuesto hay que activar los tags `Project`/`Environment` como *cost allocation tags* en la consola de AWS Billing.

## 5. Evidencias

Ejecutá `./scripts/collect-evidence.sh` (guarda salidas de `kubectl` en `docs/evidencias/`) y agregá capturas:

| Evidencia | Archivo | Estado |
|---|---|---|
| Ejecución verde de CI (tests, SAST, push a GHCR) | `docs/evidencias/ci.png` | ☐ |
| `terraform plan`/`apply` en Actions | `docs/evidencias/terraform.png` | ☐ |
| Ejecución de CD con rollout y smoke test | `docs/evidencias/cd.png` | ☐ |
| `kubectl get pods,svc,ingress,hpa` | `docs/evidencias/*-app-resources.txt` | ☐ |
| HPA escalando bajo carga | `docs/evidencias/hpa.png` | ☐ |
| Dashboard de Grafana con métricas | `docs/evidencias/grafana.png` | ☐ |
| Target UP en Prometheus | `docs/evidencias/prometheus.png` | ☐ |
| Reporte de ZAP | `docs/evidencias/zap.png` | ☐ |
| Resultados de CodeQL / Trivy | `docs/evidencias/sast.png` | ☐ |

## 6. Problemas frecuentes

- **`ImagePullBackOff`:** el paquete de GHCR es privado → hacerlo público o usar `imagePullSecret`.
- **HPA muestra `<unknown>`:** metrics-server no está listo; esperar o revisar `kubectl -n kube-system get pods`.
- **Ingress sin dirección:** el balanceador tarda unos minutos en crearse; `kubectl -n ingress-nginx get svc`.
- **`terraform init` falla en el backend:** verificar bucket/tabla/región y que el rol OIDC pueda asumirse (el `github_repo` del bootstrap debe coincidir exactamente).
