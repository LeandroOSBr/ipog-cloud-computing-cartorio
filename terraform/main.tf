terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "Demonstracao"
      Compliance  = "CNJ-Provimento-213-2026"
      ManagedBy   = "Terraform"
    }
  }
}

# Gerador de sufixo aleatório para garantir nomes únicos de buckets S3
resource "random_id" "bucket_suffix" {
  byte_length = 4
}
