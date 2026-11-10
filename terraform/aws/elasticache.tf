# ElastiCache (Redis): el mismo papel que el Deployment "redis" de Kubernetes.
# Lo comparten Beanstalk y Lambda, así que el contador es uno solo para los dos.

resource "random_password" "redis" {
  length  = 32
  special = false # el AUTH de ElastiCache no admite cualquier símbolo
}

resource "aws_elasticache_subnet_group" "this" {
  name       = local.nombre
  subnet_ids = aws_subnet.privada[*].id
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = local.nombre
  description          = "Contador de visitas (${var.entorno})"
  engine               = "redis"
  engine_version       = "7.1"
  parameter_group_name = "default.redis7"
  node_type            = var.tipo_nodo_cache
  port                 = 6379

  # 1 nodo en dev; en prod, primario + réplica en otra zona y failover automático.
  num_cache_clusters         = var.nodos_cache
  automatic_failover_enabled = var.nodos_cache > 1
  multi_az_enabled           = var.nodos_cache > 1

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  # Con contraseña (AUTH) ElastiCache exige TLS: por eso la app lleva REDIS_TLS=1.
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  auth_token                 = random_password.redis.result

  snapshot_retention_limit = var.entorno == "prod" ? 7 : 0
  apply_immediately        = var.entorno != "prod"
}

locals {
  # Las mismas variables que el Deployment de Kubernetes, más REDIS_TLS.
  # Nota: así la contraseña queda visible en la consola de Beanstalk y Lambda;
  # en un proyecto real se leería de Secrets Manager.
  entorno_app = {
    ENTORNO        = var.entorno
    APP_VERSION    = var.version_app
    REDIS_HOST     = aws_elasticache_replication_group.this.primary_endpoint_address
    REDIS_PORT     = "6379"
    REDIS_PASSWORD = random_password.redis.result
    REDIS_TLS      = "1"
  }
}
