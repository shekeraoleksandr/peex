variable "region" {
  description = "AWS region (must match the 11-network stack)"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name prefix for the alarm/topic resources"
  type        = string
  default     = "peex-containers"
}

variable "alert_email" {
  description = <<-EOT
    E-mail address that receives alarm notifications. AWS sends a confirmation
    message to this address; the subscription is inactive until you click the
    link in it.
  EOT
  type = string
}

variable "cpu_threshold" {
  description = "CPU percentage above which the alarm fires (two 5-minute periods)"
  type        = number
  default     = 80
}
