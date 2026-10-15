---
title: "Proyecto Final – Pipeline CI/CD, Infraestructura como Código y Kubernetes"
author: "[NOMBRE Y APELLIDO]"
date: "[FECHA DE ENTREGA]"
---

# 1. Introducción y objetivo

El objetivo de este proyecto fue construir un pipeline completo de DevOps: una aplicación contenerizada, infraestructura en la nube definida como código, integración y despliegue continuos, ejecución en Kubernetes con auto-escalado, observabilidad con Prometheus y Grafana, análisis de seguridad (SAST y DAST) y medidas de optimización de costos (FinOps).

Como no se contaba con una aplicación previa ni con una nube definida, se tomaron estas decisiones:

| Decisión | Elección | Motivo |
|---|---|---|
| Aplicación | API REST en Node.js (Express) | Simple, con tests y métricas Prometheus nativas |
| Nube | AWS (VPC + EKS) | Kubernetes gestionado, amplia documentación |
| CI/CD | GitHub Actions | Integrado al repositorio; permite OIDC hacia AWS |
| Registry | GitHub Container Registry (GHCR) | Gratuito y sin credenciales adicionales |
| IaC | Terraform con módulos propios | Reutilizable y parametrizable por entorno |
| Monitoreo | kube-prometheus-stack (Helm) | Prometheus, Grafana y exporters en un solo chart |
| SAST / DAST | CodeQL + Trivy / OWASP ZAP | Cubren código, IaC, imagen y aplicación en ejecución |

**Repositorio:** [PEGAR URL DEL REPOSITORIO]

# 2. Arquitectura

```
git push -> GitHub Actions
  CI:    tests -> SAST (CodeQL, Trivy IaC) -> build -> Trivy imagen -> push a GHCR
  Infra: terraform fmt/validate/plan/apply (OIDC, sin claves largas)
  CD:    helm (metrics-server, ingress-nginx, kube-prometheus-stack)
         -> kubectl apply -k k8s/base -> smoke test -> DAST (ZAP)

AWS: VPC (subnets públicas/privadas) -> EKS (node group spot)
     -> ingress-nginx (balanceador) -> Service -> Pods (HPA 2 a 8)
Monitoreo: ServiceMonitor -> Prometheus -> Grafana
```

# 3. Aplicación

Se desarrolló una API con los endpoints `/` (información), `/health` (salud), `/api/sum` (lógica con validación), `/api/load` (consumo de CPU controlado, usado para demostrar el HPA) y `/metrics` (formato Prometheus: contador de requests, histograma de latencia y métricas por defecto del proceso). Incluye 4 tests automatizados con el runner nativo de Node (`node --test`) y apagado ordenado ante `SIGTERM`, lo que permite a Kubernetes reemplazar pods sin cortar solicitudes.

# 4. Docker

El `Dockerfile` usa **multi-stage build** con tres etapas:

1. `deps`: instala solo dependencias de producción.
2. `test`: instala todo y ejecuta los tests; si fallan, el build falla.
3. `runtime`: imagen final basada en `node:20-alpine` que copia únicamente `node_modules` de producción y el código.

Optimizaciones y seguridad: imagen mínima, `.dockerignore`, caché de capas, usuario **no root con UID numérico 10001** (necesario para que Kubernetes pueda verificar `runAsNonRoot`), `HEALTHCHECK` y `NODE_ENV=production`.

# 5. Terraform

Estructura:

- `terraform/` (raíz): `versions.tf`, `backend.tf` (S3 con configuración parcial para no fijar nombres en el repo), `variables.tf`, `main.tf`, `outputs.tf`.
- `modules/network`: VPC con subnets públicas y privadas, NAT Gateway (único o por zona), etiquetas para balanceadores (basado en `terraform-aws-modules/vpc`).
- `modules/cluster`: cluster EKS y node group administrado, con capacidad spot u on-demand, tamaños mínimo/deseado/máximo y restricción de CIDR para el endpoint público (basado en `terraform-aws-modules/eks`).
- `modules/finops`: apagado/encendido programado de nodos y presupuesto mensual con alertas.
- `envs/dev.tfvars` y `envs/prod.tfvars`: valores por entorno.
- `bootstrap/`: se ejecuta una vez a mano; crea el bucket S3 versionado y cifrado, la tabla DynamoDB de locks, el proveedor OIDC de GitHub y el rol IAM que asume el pipeline.

Se usan variables con validaciones (por ejemplo, `environment` solo admite `dev` o `prod`) y `default_tags` para etiquetar todos los recursos.

# 6. Pipeline CI/CD

**ci.yml** – se ejecuta en cada push/PR:

- *test*: `npm ci`, tests y `npm audit` (dependencias de producción).
- *sast*: CodeQL sobre el código y Trivy `config` sobre Terraform y manifiestos Kubernetes.
- *image*: build con el Dockerfile multi-stage, escaneo Trivy de la imagen (falla ante vulnerabilidades críticas con parche disponible) y push a GHCR con tags `<sha>` y `latest` (solo en `main`).

**infra.yml** – manual (`workflow_dispatch`) y en PRs que tocan `terraform/**`: `fmt`, `init` con backend remoto, `validate`, `plan` y, a pedido, `apply` o `destroy`. Se autentica por **OIDC**, sin claves de larga duración, y usa *GitHub Environments* para permitir aprobaciones.

**cd.yml** – se dispara cuando CI termina correctamente en `main`: configura `kubectl`, instala metrics-server, ingress-nginx y kube-prometheus-stack con Helm, fija la imagen desplegada con `kustomize edit set image` (tag = SHA del commit), aplica los manifiestos, espera el rollout, aplica el monitoreo, obtiene la URL pública y ejecuta un smoke test. Luego un job de **DAST** corre OWASP ZAP baseline contra la URL y publica el reporte como artifact.

**finops.yml** – encendido/apagado de los nodos del entorno de pruebas, manual o programado.

## 6.1 Secretos y variables

| Tipo | Nombre | Uso |
|---|---|---|
| Secret | `AWS_ROLE_ARN` | Rol que asume el pipeline por OIDC |
| Secret | `GRAFANA_ADMIN_PASSWORD` | Contraseña de Grafana |
| Variable | `AWS_REGION`, `TF_STATE_BUCKET`, `TF_LOCK_TABLE`, `CLUSTER_NAME` | Configuración no sensible |

Ninguna credencial figura en el repositorio.

# 7. Kubernetes

Manifiestos en `k8s/base` (gestionados con Kustomize):

- **Namespace** `pf-devops`.
- **Deployment**: 2 réplicas, estrategia `RollingUpdate` sin indisponibilidad (`maxUnavailable: 0`), probes de readiness y liveness sobre `/health`, requests/limits de CPU y memoria, y contexto de seguridad (no root, filesystem de solo lectura, sin capabilities, seccomp).
- **Service** `ClusterIP` en el puerto 80.
- **Ingress** con clase `nginx`, que expone la aplicación hacia afuera.
- **HorizontalPodAutoscaler** (v2): 2 a 8 réplicas, objetivo 60 % de CPU y 80 % de memoria, con políticas de escalado rápido hacia arriba y gradual hacia abajo.
- **PodDisruptionBudget** con `minAvailable: 1`.

Además existe un *overlay* `k8s/overlays/local` para correr todo en un cluster local con kind.

# 8. Monitoreo

Se instala `kube-prometheus-stack` con valores propios (`k8s/monitoring/kube-prometheus-stack-values.yaml`). Un **ServiceMonitor** indica a Prometheus que recolecte `/metrics` de la aplicación cada 15 segundos. Un **dashboard de Grafana** (provisionado por ConfigMap con la etiqueta `grafana_dashboard`) muestra: requests por segundo, latencia p95, CPU y memoria por pod, réplicas actuales vs. deseadas del HPA y errores 5xx. Se definieron además dos alertas (`AppDown` y `HighErrorRate`) como `PrometheusRule`.

# 9. Seguridad

- Gestión de secretos fuera del repositorio; autenticación por OIDC.
- Contenedor mínimo, no root, con restricciones de runtime.
- SAST: CodeQL, Trivy IaC y `npm audit`; escaneo de la imagen antes de publicarla.
- DAST: OWASP ZAP baseline sobre el despliegue real.
- Estado de Terraform remoto, cifrado y con bloqueo; endpoint del API restringible por CIDR.

Limitaciones conocidas (se dejan documentadas): el rol de CI tiene permisos amplios para simplificar el entorno de práctica, no se configuró TLS en el Ingress y no hay NetworkPolicies.

# 10. FinOps

| Medida | Implementación |
|---|---|
| Nodos spot en desarrollo | `node_capacity_type = "SPOT"` |
| Un solo NAT Gateway en desarrollo | `single_nat_gateway = true` |
| Apagado nocturno de nodos | `aws_autoscaling_schedule` y workflow `finops.yml` |
| Auto-escalado de pods | HPA 2–8 réplicas |
| Requests/limits ajustados | Mejor aprovechamiento de los nodos |
| Retención corta de métricas y Alertmanager deshabilitado | Menos disco y cómputo |
| Etiquetado de costos | `default_tags` (`Project`, `Environment`, `CostCenter`) |
| Presupuesto mensual con alertas al 80 % y 100 % | Módulo `finops` |

# 11. Cómo replicar el pipeline

Los pasos completos y verificados paso a paso están en el `README.md` del repositorio: ejecución local (app, Docker y kind), bootstrap de Terraform, configuración de secretos y variables en GitHub, provisionamiento, despliegue, validación, pruebas de carga del HPA, acceso a Grafana/Prometheus y destrucción del entorno.

# 12. Evidencias

> Reemplazar cada marcador por la captura o salida real obtenida al ejecutar el pipeline.

**12.1 CI en verde (tests, SAST, push a GHCR)**

[PEGAR CAPTURA: pestaña Actions, workflow CI]

**12.2 Terraform plan y apply**

[PEGAR CAPTURA: workflow Infra y outputs de terraform]

**12.3 CD: rollout y smoke test**

[PEGAR CAPTURA: workflow CD]

**12.4 Recursos en Kubernetes**

[PEGAR SALIDA: `kubectl -n pf-devops get pods,svc,ingress,hpa`]

**12.5 HPA bajo carga**

[PEGAR CAPTURA: `kubectl get hpa -w` mostrando el aumento de réplicas]

**12.6 Prometheus**

[PEGAR CAPTURA: Status → Targets con `pf-devops-app` en estado UP]

**12.7 Grafana**

[PEGAR CAPTURA: dashboard "PF DevOps - Aplicación"]

**12.8 Seguridad**

[PEGAR CAPTURA: resultados de CodeQL/Trivy y reporte de ZAP]

# 13. Problemas encontrados y aprendizajes

[COMPLETAR con los problemas reales que aparezcan durante la ejecución y cómo se resolvieron. Ejemplos habituales: `ImagePullBackOff` por paquete privado en GHCR, HPA en `<unknown>` hasta que metrics-server está listo, tiempo de creación del balanceador.]

# 14. Conclusiones

El proyecto integra de forma automatizada la construcción, prueba, análisis de seguridad, publicación y despliegue de una aplicación sobre infraestructura declarada como código, con escalado automático, observabilidad y controles de costo. La separación en módulos, el uso de variables por entorno y la documentación permiten que otra persona reproduzca y valide el pipeline sin asistencia.

# Anexo: historial de commits

[PEGAR SALIDA DE: `git log --oneline`]
