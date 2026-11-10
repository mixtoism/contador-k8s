terraform {
  # mock_provider en terraform test (1.7) y validaciones entre variables (1.9)
  required_version = ">= 1.9"

  required_providers {
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

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Proyecto   = "contador-k8s"
      Entorno    = var.entorno
      Plataforma = var.plataforma
    }
  }
}
