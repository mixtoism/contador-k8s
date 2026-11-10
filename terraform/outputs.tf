output "namespace" {
  value = module.contador.namespace
}

output "url" {
  description = "URL local: el clúster publica el NodePort 300xx en el puerto 80xx del host"
  value       = "http://localhost:${var.node_port - 22000}"
}

output "replicas" {
  value = module.contador.replicas
}
