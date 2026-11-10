# Lo que necesita cualquier despliegue en AWS: la red y el Redis gestionado.
# Dos zonas, cada una con una subred pública (Beanstalk y su balanceador) y una privada
# (ElastiCache y la Lambda). Sin NAT: lo privado sólo habla con Redis.

data "aws_availability_zones" "disponibles" {
  state = "available"
}

locals {
  zonas = slice(data.aws_availability_zones.disponibles.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = var.nombre }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "publica" {
  count                   = length(local.zonas)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.zonas[count.index]
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.nombre}-publica-${count.index}" }
}

resource "aws_subnet" "privada" {
  count             = length(local.zonas)
  vpc_id            = aws_vpc.this.id
  availability_zone = local.zonas[count.index]
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, 100 + count.index)
  tags              = { Name = "${var.nombre}-privada-${count.index}" }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "publica" {
  count          = length(aws_subnet.publica)
  subnet_id      = aws_subnet.publica[count.index].id
  route_table_id = aws_route_table.publica.id
}

# ---------- Security groups: sólo la app puede hablar con Redis ----------

resource "aws_security_group" "app" {
  name        = "${var.nombre}-app"
  description = "La app (instancias de Beanstalk o la Lambda)"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redis" {
  name        = "${var.nombre}-redis"
  description = "ElastiCache: solo acepta 6379 desde la app"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Redis desde la app"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
}

# ---------- ElastiCache: el papel del Deployment "redis" de Kubernetes ----------

resource "random_password" "redis" {
  length  = 32
  special = false # el AUTH de ElastiCache no admite cualquier símbolo
}

resource "aws_elasticache_subnet_group" "this" {
  name       = var.nombre
  subnet_ids = aws_subnet.privada[*].id
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.nombre
  description          = "Contador de visitas (${var.nombre})"
  engine               = "redis"
  engine_version       = "7.1"
  parameter_group_name = "default.redis7"
  node_type            = var.tipo_nodo
  port                 = 6379

  # 1 nodo en dev; en prod, primario + réplica en otra zona y failover automático.
  num_cache_clusters         = var.nodos
  automatic_failover_enabled = var.nodos > 1
  multi_az_enabled           = var.nodos > 1

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  # Con contraseña (AUTH) ElastiCache exige TLS: por eso la app lleva REDIS_TLS=1.
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  auth_token                 = random_password.redis.result

  snapshot_retention_limit = var.nodos > 1 ? 7 : 0
  apply_immediately        = true
}
