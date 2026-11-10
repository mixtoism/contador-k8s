# El mismo módulo que en local; sólo cambian la imagen (de ECR) y el Service,
# que en la nube es un LoadBalancer.
module "contador" {
  source = "../modules/contador"

  entorno       = var.entorno
  replicas      = var.replicas
  imagen        = "${aws_ecr_repository.contador.repository_url}:${var.version_app}"
  version_app   = var.version_app
  tipo_servicio = "LoadBalancer"

  depends_on = [aws_eks_node_group.this]
}
