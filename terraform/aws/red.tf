# VPC mínima: dos subredes públicas. Suficiente para una demo; en producción
# los nodos irían en subredes privadas con NAT.
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "contador-${var.entorno}" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "publica" {
  count                   = length(var.zonas)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.zonas[count.index]
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name                     = "contador-${var.entorno}-${var.zonas[count.index]}"
    "kubernetes.io/role/elb" = "1" # aquí crea EKS los balanceadores
  }
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
