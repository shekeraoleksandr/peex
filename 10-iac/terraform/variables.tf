variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_prefix" {
  description = "Globally-unique prefix for the bucket name"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "enable_versioning" {
  description = "Toggle S3 object versioning (flip this to demo a config change)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default = {
    Project    = "PeEx"
    Competency = "iac"
  }
}
