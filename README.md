# contador-k8s

Demo de despliegue en **Kubernetes con Terraform**. La app es un contador de visitas
(Node, sin dependencias) con Redis. **Cada pod pinta la página de un color distinto**,
así que al recargar se ve qué réplica responde.

Todo corre en contenedores con **podman**: el clúster (k3s en un contenedor), Terraform
(`hashicorp/terraform`), Helm (`alpine/helm`) y la construcción de la imagen. Aparte de
podman, sólo hace falta `kubectl` para la vía de manifiestos.

La misma app se despliega en **seis entornos con Terraform**: cada uno es un workspace
con su `.tfvars`, y se manejan todos igual (`make <entorno>`, `make plan-<entorno>`,
`make destruir-<entorno>`):

| Entorno | Dónde | Cómo corre la app | Redis |
|---|---|---|---|
| `dev-kube` · `prod-kube` | k3s local → :8080 · :8081 | Deployment de pods (1 · 3 réplicas) | Deployment en el clúster |
| `dev-beanstalk` · `prod-beanstalk` | AWS (PaaS) | **Elastic Beanstalk**: ALB → EC2 (1-2 · 2-4) | **ElastiCache** (1 · 2 nodos) |
| `dev-lambda` · `prod-lambda` | AWS (serverless) | **API Gateway → Lambda** (tope 2 · sin tope) | **ElastiCache** (1 · 2 nodos) |

Los de Kubernetes se prueban de verdad, en local y en el CI. Los de AWS se prueban
**simulados** (`make aws-test`, sin cuenta) y se pueden desplegar de verdad con una cuenta.

En Kubernetes hay además otras **dos vías** de despliegue, para comparar con Terraform:

| Vía | Dónde | dev | prod |
|---|---|---|---|
| **Manifiestos + kustomize** | `k8s/base`, `k8s/dev`, `k8s/prod` | :8082 | :8083 |
| **Helm** | `helm/contador` + `values-{dev,prod}.yaml` | :8084 | :8085 |

```
app/                 servidor Node (sin dependencias) + Dockerfile + run.sh (arranque en Lambda)
terraform/           entornos *-kube: dev-kube.tfvars, prod-kube.tfvars
  modules/contador/  namespace, Secret, Redis, Deployment, Service
  aws/               entornos *-lambda y *-beanstalk: VPC, ElastiCache, Beanstalk, Lambda;
                     tests/ con mocks
k8s/                 YAML "a pelo" y overlays de kustomize
helm/contador/       chart con plantillas, helm test y NOTES
scripts/             cluster.sh, tf.sh, helm.sh, probar.sh, diagnostico.sh
.github/workflows/   CI
```

En todos los casos, dev y prod son **las mismas plantillas con distintos valores**
(`.tfvars`, overlay de kustomize, `values-*.yaml`).

## En local

```bash
make cluster            # k3s en podman; deja ./kubeconfig
make imagen             # construye localhost/contador:v1 y la carga en el clúster
make dev-kube prod-kube # Terraform            → localhost:8080 y :8081
make yaml-dev yaml-prod # vía kubectl -k       → :8082 y :8083
make helm-dev helm-prod # vía Helm             → :8084 y :8085
make aws-test           # entornos de AWS, simulados (sin cuenta)
make help               # todos los objetivos
```

Para actualizar: `make imagen TAG=v2` y luego `make helm-prod TAG=v2` (o
`scripts/tf.sh prod-kube apply -var imagen=localhost/contador:v2 -var version_app=v2`).

Comandos sueltos: `scripts/tf.sh <entorno> <comando>` (y `kube`/`aws` sin entorno para
`fmt`, `validate`, `test`), `scripts/helm.sh <args>`,
y para kubectl `export KUBECONFIG=$PWD/kubeconfig`.

Al terminar: `make borrar` (se lleva todo el clúster por delante).

> **Podman rootless** necesita el controlador `cpuset` delegado (k3s y kind lo exigen).
> Si `make cluster` falla con `failed to find cpuset cgroup`:
>
> ```bash
> sudo mkdir -p /etc/systemd/system/user@.service.d
> printf '[Service]\nDelegate=cpu cpuset io memory pids\n' | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
> sudo systemctl daemon-reload   # y cerrar sesión / reiniciar
> ```
>
> Alternativa sin tocar eso: anteponer `MOTOR="sudo podman"` a los `make`.

## AWS: PaaS y serverless

El **mismo `app/`**, sin cambiar una línea, es lo que se despliega en los entornos de AWS.
Todos comparten las plantillas de `terraform/aws/`; la variable `plataforma` del `.tfvars`
decide qué se crea:

```
*-beanstalk:  navegador ─▶ ALB ─▶ Elastic Beanstalk (EC2, Node.js 22) ─▶ ElastiCache (Redis, TLS)
*-lambda:     navegador ─▶ API Gateway ─▶ Lambda (+ Web Adapter) ───────▶ ElastiCache (Redis, TLS)
```

Cada entorno tiene su propia red y su propio ElastiCache, como cada entorno de
Kubernetes tiene su namespace y su Redis.

| En Kubernetes | Elastic Beanstalk (PaaS) | Lambda (serverless) |
|---|---|---|
| imagen de contenedor | zip de `app/` en S3, *application version* | el mismo zip |
| cómo arranca | `npm start` (plataforma Node.js 22) | `run.sh`, vía la capa **Lambda Web Adapter** |
| Deployment + pods | instancias EC2 en un Auto Scaling Group | copias calientes de la función |
| `replicas` | `MinSize` / `MaxSize` | `reserved_concurrent_executions` (tope) |
| Service NodePort | **Application Load Balancer** | **API Gateway** (HTTP API) |
| `readinessProbe` `/readyz` | `HealthCheckPath=/readyz` del balanceador | `AWS_LWA_READINESS_CHECK_PATH` |
| RollingUpdate | `DeploymentPolicy=Rolling`, lotes de 1 | cada versión sustituye a la anterior |
| Redis + Secret | **ElastiCache** con `auth_token` y TLS | la misma |
| `kubectl logs` | CloudWatch Logs (`StreamLogs`) | CloudWatch Logs |

Ficheros en `terraform/aws/`:

- `main.tf`: el nombre del entorno, `es_beanstalk` / `es_lambda` y el zip de `app/`.
- `red.tf`: VPC con dos zonas; subredes públicas para Beanstalk, privadas para Redis y
  la Lambda. Security groups: Redis sólo acepta el 6379 desde la app.
- `elasticache.tf`: *replication group* de Redis 7. En dev, un nodo; en prod, primario
  + réplica en otra zona con failover automático y copias diarias.
- `beanstalk.tf`: bucket S3 con las versiones, aplicación, entorno y roles IAM.
- `lambda.tf`: la función en la VPC, con la capa Web Adapter, y API Gateway delante.
- `dev-beanstalk.tfvars`, `prod-beanstalk.tfvars`, `dev-lambda.tfvars`, `prod-lambda.tfvars`.

Los recursos de cada plataforma llevan `count = local.es_beanstalk ? 1 : 0` (o
`es_lambda`): en un entorno de Lambda, Beanstalk existe 0 veces. Por eso se escriben
`aws_lambda_function.contador[0]`, y por eso `outputs.tf` da una sola `url`, la que exista.

Un detalle: ElastiCache sólo admite contraseña con cifrado en tránsito, así que la app
se conecta por TLS cuando lleva `REDIS_TLS=1` (`app/redis.js`). Para simplificar, la
contraseña va en las variables de entorno; en un proyecto real se leería de Secrets Manager.

`make aws-test` lo prueba **sin cuenta ni credenciales**: `terraform test` con
`mock_provider` para `aws` y `archive` hace *plan* y *apply* de verdad, pero los
recursos sólo existen en memoria. Las pruebas (`aws/tests/mock.tftest.hcl`) tienen un
*run* por entorno y comprueban que cada uno crea sólo su plataforma, el zip de `app/`, el
health check, el despliegue por lotes, TLS, el failover en prod, que Redis sólo admite a
la app y que se rechazan un entorno o una plataforma inválidos y un `instancias_min`
mayor que el máximo.

### Desplegarlo de verdad

El CI no lo hace. Hace falta el CLI `aws` con sesión iniciada (`aws login`, `aws sso login`
o claves); `scripts/tf.sh` le pide credenciales temporales y se las pasa al contenedor.

```sh
aws sts get-caller-identity   # comprobar la cuenta
make plan-dev-lambda          # qué se crearía, sin crear nada
make dev-lambda               # init + apply (pide confirmación); ~10-15 min
scripts/tf.sh dev-lambda output
make destruir-dev-lambda      # destruirlo al acabar
```

Igual con `dev-beanstalk`, `prod-lambda` y `prod-beanstalk`; pueden convivir.
**Cuesta dinero** mientras exista (ElastiCache siempre; en Beanstalk, también EC2 y el
ALB): no olvides el `destruir-*`.
El estado queda en local (`terraform/aws/terraform.tfstate.d/`); no lo borres antes de
destruir, o habrá que borrar los recursos a mano.

## En GitHub Actions

Cada push a `main` valida todo (`fmt`, `validate`, `helm lint`, `kustomize build`),
pasa las pruebas de AWS en mock y, en paralelo, levanta clústeres k3s dentro del runner
(sin cuenta en la nube): uno por cada vía alternativa (yaml y helm: instalar, probar,
actualizar con Helm, desinstalar) y otro para `dev-kube` y `prod-kube`:

1. **Instalar** — `terraform apply` con v1.
2. **Actualizar** — v2: rolling update sin cortes (`max_unavailable = 0`).
3. **Escalar** — 5 réplicas y comprueba que responden 5 pods distintos.
4. **Drift** — escala a mano con `kubectl` y `terraform plan` lo detecta.
5. **Eliminar** — `terraform destroy`.

El **resumen de la ejecución** muestra la línea `Plan:` de cada fase y una tabla con
cuántas peticiones atendió cada pod. Es lo que conviene proyectar.

## Experimentos para clase

1. **Autorreparación**: `kubectl -n contador-prod delete pod -l app=contador --wait=false`
   y recargar: aparecen colores nuevos, el contador sigue (vive en Redis).
2. **Escalado declarativo**: cambia `replicas` en `prod-kube.tfvars`, `make plan-prod-kube`
   (`1 to change`) y `make prod-kube`.
3. **Drift**: `kubectl -n contador-prod scale deploy/contador --replicas=1` y luego
   `make plan-prod-kube`: Terraform quiere volver a 3.
4. **Actualización continua**: en una terminal
   `while sleep 0.2; do curl -s localhost:8081/api; done` y en otra
   `scripts/tf.sh prod-kube apply -var version_app=v2`: la versión cambia sin errores.
5. **Mismo código, otro entorno**: `make plan-dev-kube` vs `make plan-prod-kube`; y en
   AWS, `make plan-dev-lambda` vs `make plan-dev-beanstalk` (con cuenta).
6. **Secreto generado**: la contraseña de Redis la crea Terraform (`random_password`);
   mira `kubectl -n contador-dev get secret redis -o yaml`… y que también está en el
   `terraform.tfstate`: por eso el estado nunca se sube al repo.

## Endpoints

| Ruta | Qué hace |
|---|---|
| `/` | página con el contador y el color del pod |
| `/api` | lo mismo en JSON (suma una visita) |
| `/stats` | visitas por pod |
| `/healthz` · `/readyz` | liveness · readiness (comprueba Redis) |
