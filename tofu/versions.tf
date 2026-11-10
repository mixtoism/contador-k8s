terraform {
  # OpenTofu 1.8+: mock_provider en tofu test y validaciones entre variables
  # (el bloque se sigue llamando "terraform": OpenTofu es compatible)
  required_version = ">= 1.8"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Los dos proveedores se declaran siempre, pero cada uno sólo trabaja si se elige su
# plataforma. Con plataforma = "kube" el de AWS no pide credenciales (no va a crear nada).
provider "kubernetes" {
  config_path    = var.plataforma == "kube" ? var.kubeconfig : null
  config_context = var.plataforma == "kube" ? var.kube_context : null
}

provider "aws" {
  region = var.region

  access_key                  = local.en_aws ? null : "sin-uso"
  secret_key                  = local.en_aws ? null : "sin-uso"
  skip_credentials_validation = !local.en_aws
  skip_requesting_account_id  = !local.en_aws
  skip_metadata_api_check     = !local.en_aws

  default_tags {
    tags = {
      Proyecto   = "contador-k8s"
      Entorno    = var.entorno
      Plataforma = var.plataforma
    }
  }
}
