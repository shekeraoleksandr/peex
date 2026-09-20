terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Provision a resource from this template: an S3 bucket parameterized by
# variables. Change a variable (e.g. enable_versioning, tags) and re-apply to
# execute an automated configuration change.
resource "aws_s3_bucket" "iac_demo" {
  bucket = "${var.bucket_prefix}-${var.environment}"
  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

resource "aws_s3_bucket_versioning" "iac_demo" {
  bucket = aws_s3_bucket.iac_demo.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_public_access_block" "iac_demo" {
  bucket                  = aws_s3_bucket.iac_demo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "iac_demo" {
  bucket = aws_s3_bucket.iac_demo.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
