# Prueba del despliegue en AWS sin AWS: todos los proveedores están simulados.
# Terraform hace plan y apply de verdad, pero los recursos sólo existen en memoria.
#   scripts/tf.sh aws test

mock_provider "aws" {
  mock_resource "aws_eks_cluster" {
    defaults = {
      endpoint              = "https://ABCDEF.gr7.eu-west-1.eks.amazonaws.com"
      certificate_authority = [{ data = "bW9jaw==" }] # base64("mock")
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_ecr_repository" {
    defaults = { repository_url = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/contador" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_eks_cluster_auth" {
    defaults = { token = "token-falso" }
  }
}

mock_provider "kubernetes" {}
mock_provider "random" {}

run "plan_dev" {
  command = plan

  variables {
    entorno = "dev"
  }

  assert {
    condition     = length(aws_subnet.publica) == 2
    error_message = "EKS necesita subredes en dos zonas."
  }
  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == 2
    error_message = "Por defecto hay dos nodos."
  }
}

run "despliegue_prod" {
  command = apply

  variables {
    entorno        = "prod"
    replicas       = 3
    nodos          = 3
    tipo_instancia = "t3.medium"
    version_app    = "v2"
  }

  assert {
    condition     = output.replicas == 3
    error_message = "prod debe tener 3 réplicas."
  }
  assert {
    condition     = output.imagen == "123456789012.dkr.ecr.eu-west-1.amazonaws.com/contador:v2"
    error_message = "La imagen debe venir de ECR con la versión pedida."
  }
  assert {
    condition     = aws_eks_cluster.this.name == "contador-prod"
    error_message = "Nombre de clúster inesperado."
  }
}

run "entorno_invalido" {
  command = plan

  variables {
    entorno = "staging"
  }

  expect_failures = [var.entorno]
}
