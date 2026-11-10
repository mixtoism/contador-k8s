output "cluster" {
  value = aws_eks_cluster.this.name
}

output "endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "ecr" {
  description = "Dónde subir la imagen: podman push <imagen> <ecr>:<versión>"
  value       = aws_ecr_repository.contador.repository_url
}

output "imagen" {
  value = module.contador.imagen
}

output "replicas" {
  value = module.contador.replicas
}

output "kubeconfig" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name}"
}
