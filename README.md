# contador-k8s

Demo de despliegue en **Kubernetes con Terraform**. La app es un contador de visitas
(Node, sin dependencias) con Redis. **Cada pod pinta la página de un color distinto**,
así que al recargar se ve qué réplica responde.

Todo corre en contenedores con **podman**: el clúster (k3s en un contenedor), Terraform
(`hashicorp/terraform`) y la construcción de la imagen. No hay que instalar nada más.

```
app/            servidor Node + Dockerfile
terraform/      namespace, Secret, Redis, Deployment y Service NodePort
  dev.tfvars    1 réplica  → http://localhost:8080
  prod.tfvars   3 réplicas → http://localhost:8081
scripts/        cluster.sh (k3s), tf.sh (terraform en contenedor), probar.sh
.github/        CI: valida y recorre instalar → actualizar → escalar → eliminar
```

Los dos entornos usan **los mismos `.tf` con distinto `.tfvars`**, y cada uno tiene su
propio estado (workspace de Terraform `dev` / `prod`).

## En local

```bash
make cluster          # k3s en podman; deja ./kubeconfig
make imagen           # construye localhost/contador:v1 y la carga en el clúster
make dev              # terraform apply con dev.tfvars
make prod             # terraform apply con prod.tfvars
xdg-open http://localhost:8081
```

Cualquier comando de Terraform: `scripts/tf.sh <dev|prod> <comando> [args]`, p. ej.
`scripts/tf.sh prod plan -var replicas=5`. Para kubectl:
`export KUBECONFIG=$PWD/kubeconfig` o `podman exec contador-k3s kubectl …`.

Al terminar: `make destruir-dev destruir-prod borrar`.

> **Podman rootless** necesita el controlador `cpuset` delegado (k3s y kind lo exigen).
> Si `make cluster` falla con `failed to find cpuset cgroup`:
>
> ```bash
> sudo mkdir -p /etc/systemd/system/user@.service.d
> printf '[Service]\nDelegate=cpu cpuset io memory pids\n' | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
> sudo systemctl daemon-reload   # y cerrar sesión / reiniciar
> ```
>
> Alternativa sin tocar eso: `make cluster imagen dev MOTOR="sudo podman"`.

## En GitHub Actions

Cada push a `main` crea un clúster k3s dentro del runner (sin cuenta en la nube) y,
para `dev` y `prod` en paralelo:

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
