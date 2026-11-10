output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "url" {
  description = "URL local (el clúster publica el NodePort en el host)"
  value       = "http://localhost:${var.node_port == 30080 ? 8080 : 8081}"
}

output "replicas" {
  value = kubernetes_deployment_v1.app.spec[0].replicas
}
