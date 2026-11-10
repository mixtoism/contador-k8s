terraform {
  required_version = ">= 1.7" # mock_provider en terraform test

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Proyecto = "contador-k8s"
      Entorno  = var.entorno
    }
  }
}
