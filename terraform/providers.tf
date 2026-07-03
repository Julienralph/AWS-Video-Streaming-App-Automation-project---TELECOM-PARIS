#version minimale requise de terraform
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"  # Téléchargé depuis registry.terraform.io
      version = "~> 5.0"         
    }
  }
}

# Configuration du provider AWS
provider "aws" {
  region = var.aws_region  # On utilise une variable (définie dans variables.tf)

  # Ces tags seront appliqués automatiquement à TOUTES les ressources créées
  default_tags {
    tags = {
      Project   = "GIN208-Video-Streaming"
      ManagedBy = "Terraform"
      Owner     = "julien-ralph"
    }
  }
}

