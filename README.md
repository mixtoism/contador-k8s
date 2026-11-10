# contador-k8s

Demo de despliegue en **Kubernetes con Terraform**. La app es un contador de visitas
(Node, sin dependencias) con Redis. **Cada pod pinta la página de un color distinto**,
así que al recargar se ve qué réplica responde.

Todo corre en contenedores con **podman**: el clúster (k3s en un contenedor), Terraform
(`hashicorp/terraform`), Helm (`alpine/helm`) y la construcción de la imagen. Aparte de
podman, sólo hace falta `kubectl` para la vía de manifiestos.

La misma app se despliega de **tres formas**, para comparar:

| Vía | Dónde | dev | prod |
|---|---|---|---|
| **Terraform** | `terraform/` (+ `modules/contador`) | :8080 | :8081 |
| **Manifiestos + kustomize** | `k8s/base`, `k8s/dev`, `k8s/prod` | :8082 | :8083 |
| **Helm** | `helm/contador` + `values-{dev,prod}.yaml` | :8084 | :8085 |
| **Terraform en AWS, serverless (mock)** | `terraform/aws` + `lambda/`: API Gateway → Lambda → DynamoDB, Bedrock | — | — |

```
app/                 servidor Node (sin dependencias) + Dockerfile
lambda/              el mismo contador como función Lambda (DynamoDB + Bedrock) y sus pruebas
terraform/           raíz local: un workspace por entorno, dev.tfvars / prod.tfvars
  modules/contador/  namespace, Secret, Redis, Deployment, Service
  aws/               API Gateway, Lambda, DynamoDB, IAM, CloudWatch; tests/ con proveedores mock
k8s/                 YAML "a pelo" y overlays de kustomize
helm/contador/       chart con plantillas, helm test y NOTES
scripts/             cluster.sh, tf.sh, helm.sh, probar.sh, diagnostico.sh
.github/workflows/   CI
```

En las tres vías, dev y prod son **las mismas plantillas con distintos valores**
(`.tfvars`, overlay de kustomize, `values-*.yaml`).

## En local

```bash
make cluster            # k3s en podman; deja ./kubeconfig
make imagen             # construye localhost/contador:v1 y la carga en el clúster
make dev prod           # vía Terraform        → localhost:8080 y :8081
make yaml-dev yaml-prod # vía kubectl -k       → :8082 y :8083
make helm-dev helm-prod # vía Helm             → :8084 y :8085
make aws-test           # Lambda y Terraform contra AWS simulado (sin cuenta)
make help               # todos los objetivos
```

Para actualizar: `make imagen TAG=v2` y luego `make helm-prod TAG=v2` (o
`scripts/tf.sh prod apply -var imagen=localhost/contador:v2 -var version_app=v2`).

Comandos sueltos: `scripts/tf.sh <dev|prod|aws> <comando>`, `scripts/helm.sh <args>`,
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

## AWS serverless, todo simulado

En AWS no se monta un clúster: el mismo contador se reparte entre **servicios gestionados**,
y cada pieza de Kubernetes tiene su equivalente:

| En Kubernetes | En AWS | Fichero |
|---|---|---|
| Service NodePort | **API Gateway** (HTTP API) con 4 rutas | `terraform/aws/api.tf` |
| Deployment + pods | **Lambda** (`nodejs22.x`, arm64); cada copia caliente tiene su color | `lambda.tf`, `lambda/` |
| `replicas` | `reserved_concurrent_executions` (tope de copias simultáneas) | `lambda.tf` |
| Redis + Secret | **DynamoDB** bajo demanda; sin contraseña: la Lambda entra por **IAM** | `dynamodb.tf` |
| `kubectl logs` | **CloudWatch Logs** con retención por entorno | `lambda.tf` |
| — | **Bedrock**: Claude escribe una frase para cada visita | `lambda/index.js` |

```
navegador ─▶ API Gateway ─▶ Lambda ─┬─▶ DynamoDB   (ADD n :1 → visitas, instancia#…)
                                     └─▶ Bedrock    (Claude: frase de la visita)
```

- `lambda/logica.js` es la lógica y no tiene dependencias: recibe los clientes de
  DynamoDB y Bedrock ya creados. `lambda/index.js` crea los de verdad: DynamoDB con el
  AWS SDK que trae el runtime, y Bedrock con el SDK oficial de Anthropic
  (`@anthropic-ai/bedrock-sdk`). Si Bedrock falla o tarda más de 8 s, la página sale
  igual, sin la frase.
- dev y prod comparten plantillas y cambian en `dev.tfvars` y `prod.tfvars`: memoria,
  tope de copias, retención de logs, copias continuas de la tabla y throttling de la API.
- `modelo_bedrock = ""` quita Bedrock: desaparecen el permiso IAM y la llamada.

`make aws-test` lo prueba **sin cuenta ni credenciales**, en dos niveles:

1. `node --test lambda/logica.test.js`: la Lambda con DynamoDB y Bedrock falsos. Comprueba el recuento
   por instancia, que la frase sale escapada en el HTML, que un fallo de Bedrock no rompe
   la página y que un fallo de DynamoDB da 503.
2. `terraform test` con `mock_provider` para `aws` y `archive`: Terraform hace *plan* y
   *apply* de verdad, pero los recursos sólo existen en memoria. Las pruebas
   (`aws/tests/mock.tftest.hcl`) comprueban las rutas, el tope de copias en dev, PITR y
   retención en prod, que el permiso de Bedrock sólo aparece si hay modelo y que un
   entorno inválido se rechaza.

Para desplegarlo de verdad (no lo hace el CI): `make lambda` instala las dependencias en
`lambda/node_modules` con un contenedor de Node. Después,
`scripts/tf.sh aws apply -var-file=dev.tfvars` con credenciales de AWS y el modelo
habilitado en Bedrock.

## En GitHub Actions

Cada push a `main` valida todo (`fmt`, `validate`, `helm lint`, `kustomize build`),
pasa las pruebas de la Lambda y de AWS en mock y, en paralelo, levanta clústeres k3s dentro del runner
(sin cuenta en la nube): uno por cada vía alternativa (yaml y helm: instalar, probar,
actualizar con Helm, desinstalar) y otro por entorno para Terraform:

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
2. **Escalado declarativo**: cambia `replicas` en `prod.tfvars`, `make plan-prod`
   (`1 to change`) y `make prod`.
3. **Drift**: `kubectl -n contador-prod scale deploy/contador --replicas=1` y luego
   `make plan-prod`: Terraform quiere volver a 3.
4. **Actualización continua**: en una terminal
   `while sleep 0.2; do curl -s localhost:8081/api; done` y en otra
   `scripts/tf.sh prod apply -var version_app=v2`: la versión cambia sin errores.
5. **Mismo código, otro entorno**: `make plan-dev` vs `make plan-prod`.
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
