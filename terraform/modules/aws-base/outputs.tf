output "vpc_id" {
  value = aws_vpc.this.id
}

output "subredes_publicas" {
  value = aws_subnet.publica[*].id
}

output "subredes_privadas" {
  value = aws_subnet.privada[*].id
}

output "sg_app" {
  description = "Security group que deben llevar las instancias o la Lambda para llegar a Redis"
  value       = aws_security_group.app.id
}

output "redis_host" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_password" {
  value     = random_password.redis.result
  sensitive = true
}
