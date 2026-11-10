# ---------- IAM ----------
data "aws_iam_policy_document" "asumir" {
  for_each = toset(["eks", "ec2"])
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["${each.key}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "contador-${var.entorno}-cluster"
  assume_role_policy = data.aws_iam_policy_document.asumir["eks"].json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "nodos" {
  name               = "contador-${var.entorno}-nodos"
  assume_role_policy = data.aws_iam_policy_document.asumir["ec2"].json
}

resource "aws_iam_role_policy_attachment" "nodos" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.nodos.name
  policy_arn = "arn:aws:iam::aws:policy/${each.key}"
}

# ---------- Clúster ----------
resource "aws_eks_cluster" "this" {
  name     = "contador-${var.entorno}"
  role_arn = aws_iam_role.cluster.arn
  version  = "1.31"

  vpc_config {
    subnet_ids = aws_subnet.publica[*].id
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "general"
  node_role_arn   = aws_iam_role.nodos.arn
  subnet_ids      = aws_subnet.publica[*].id
  instance_types  = [var.tipo_instancia]

  scaling_config {
    desired_size = var.nodos
    min_size     = 1
    max_size     = var.nodos + 2
  }

  depends_on = [aws_iam_role_policy_attachment.nodos]
}

data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}

# ---------- Registro de imágenes ----------
resource "aws_ecr_repository" "contador" {
  name                 = "contador-${var.entorno}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
}
