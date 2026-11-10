# Sólo uno de los tres módulos existe: concat + one() se queda con el que haya.

output "plataforma" {
  value = var.plataforma
}

output "url" {
  description = "La página del contador"
  value = one(concat(
    [for m in module.kube : "http://localhost:${var.node_port - 22000}"], # NodePort 300xx → puerto 80xx del host
    module.beanstalk[*].url,
    module.lambda[*].url,
  ))
}

output "logs" {
  value = one(concat(module.kube[*].logs, module.beanstalk[*].logs, module.lambda[*].logs))
}

output "namespace" {
  value = one(module.kube[*].namespace)
}

output "redis" {
  description = "Endpoint de ElastiCache (sólo en AWS)"
  value       = one([for b in module.aws_base : "${b.redis_host}:6379"])
}
