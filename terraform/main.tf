# Despliegue en el clúster local (k3s en podman).
# Los recursos de Kubernetes están en modules/contador, que también usa aws/.
module "contador" {
  source = "./modules/contador"

  entorno     = var.entorno
  replicas    = var.replicas
  imagen      = var.imagen
  version_app = var.version_app
  node_port   = var.node_port
  cpu_limite  = var.cpu_limite
}
