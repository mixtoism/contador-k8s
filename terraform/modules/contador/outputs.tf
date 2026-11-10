output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "servicio" {
  value = kubernetes_service_v1.app.metadata[0].name
}

output "replicas" {
  value = tonumber(kubernetes_deployment_v1.app.spec[0].replicas)
}

output "imagen" {
  value = kubernetes_deployment_v1.app.spec[0].template[0].spec[0].container[0].image
}
