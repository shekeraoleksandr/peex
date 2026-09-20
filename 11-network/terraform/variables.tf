variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name/tag prefix for every resource this stack creates"
  type        = string
  default     = "peex-netcompute"
}

variable "allowed_cidr" {
  description = <<-EOT
    CIDR allowed to reach SSH / Grafana / Prometheus / the web app from the
    internet. Set it to YOUR_PUBLIC_IP/32 -- never leave this at 0.0.0.0/0.
    Get it with ../scripts/get-my-ip.sh, or ./apply.sh auto-detects it if unset.
  EOT
  type = string
}

variable "vpc_cidr" {
  description = "CIDR for the whole VPC"
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the single public subnet both instances live in"
  type        = string
  default     = "10.42.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for both nodes (kept small / free-tier friendly)"
  type        = string
  default     = "t3.micro"
}

# --- added for the full network build (subnets, peering, monitoring) ---------

variable "public_subnet_b_cidr" {
  description = "Second-AZ public subnet; reserved so the stack can grow to multi-AZ without re-addressing"
  type        = string
  default     = "10.42.2.0/24"
}

variable "private_subnet_cidr" {
  description = "Private subnet: no route to the internet gateway, egress via the NAT instance"
  type        = string
  default     = "10.42.10.0/24"
}

variable "peer_vpc_cidr" {
  description = "CIDR of the second ('remote') VPC. Must not overlap vpc_cidr."
  type        = string
  default     = "10.43.0.0/16"
}

variable "peer_subnet_cidr" {
  type    = string
  default = "10.43.1.0/24"
}

# Static addresses: each IPsec endpoint needs the other's address at boot, and
# static assignment is what breaks that circular dependency.
variable "web_host_ip" {
  type    = string
  default = "10.42.1.10"
}

variable "private_host_ip" {
  type    = string
  default = "10.42.10.10"
}

variable "peer_host_ip" {
  type    = string
  default = "10.43.1.10"
}

variable "flow_log_retention_days" {
  description = "Flow logs get expensive fast; keep the window short for a demo network"
  type        = number
  default     = 1
}
