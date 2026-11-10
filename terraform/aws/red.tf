# Red: dos zonas, cada una con una subred pública (instancias de Beanstalk y su
# balanceador) y una privada (ElastiCache y la Lambda). Sin NAT: lo privado sólo
# habla con Redis, y así no hay coste fijo por NAT Gateway.

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
  tags                 = { Name = local.nombre }
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
  tags                    = { Name = "${local.nombre}-publica-${count.index}" }
}

resource "aws_subnet" "privada" {
  count             = length(local.zonas)
  vpc_id            = aws_vpc.this.id
  availability_zone = local.zonas[count.index]
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, 100 + count.index)
  tags              = { Name = "${local.nombre}-privada-${count.index}" }
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

# ---------- Security groups: quién puede hablar con Redis ----------

resource "aws_security_group" "beanstalk" {
  name        = "${local.nombre}-beanstalk"
  description = "Instancias EC2 de Elastic Beanstalk"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "lambda" {
  name        = "${local.nombre}-lambda"
  description = "Interfaces de red de la Lambda dentro de la VPC"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redis" {
  name        = "${local.nombre}-redis"
  description = "ElastiCache: sólo acepta 6379 desde Beanstalk y Lambda"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Redis desde Beanstalk y Lambda"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.beanstalk.id, aws_security_group.lambda.id]
  }
}
