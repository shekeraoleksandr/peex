# --- Secure connectivity between two private networks ------------------------
#
# Two mechanisms, layered:
#   1. VPC PEERING gives the two VPCs a private route to each other. Traffic
#      stays on the AWS backbone and never touches the public internet. Peering
#      is free; a Site-to-Site VPN gateway would be ~$36/month for the same
#      demonstration.
#   2. An IPSEC TRANSPORT-MODE TUNNEL (strongSwan, IKEv2) between the two hosts
#      encrypts the payload itself. Peering alone gives isolation, not
#      cryptography -- this closes the "traffic encrypted in transit" gap
#      rather than hand-waving it.
#
# The two endpoints get STATIC private IPs. Each side needs the other's address
# baked into its config at boot, and static addressing is what breaks that
# circular dependency.

resource "aws_vpc" "peer" {
  cidr_block           = var.peer_vpc_cidr # 10.43.0.0/16 -- no overlap with 10.42.0.0/16
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project}-peer-vpc"
    Project = "PeEx"
    Role    = "remote-network"
  }
}

resource "aws_subnet" "peer" {
  vpc_id            = aws_vpc.peer.id
  cidr_block        = var.peer_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name    = "${var.project}-peer-subnet"
    Project = "PeEx"
  }
}

resource "aws_route_table" "peer" {
  vpc_id = aws_vpc.peer.id

  tags = {
    Name    = "${var.project}-peer-rt"
    Project = "PeEx"
  }
}

resource "aws_route_table_association" "peer" {
  subnet_id      = aws_subnet.peer.id
  route_table_id = aws_route_table.peer.id
}

# ------------------------------------------------------------------- peering
resource "aws_vpc_peering_connection" "main_to_peer" {
  vpc_id      = aws_vpc.main.id
  peer_vpc_id = aws_vpc.peer.id
  auto_accept = true # same account and region, so no separate accepter needed

  tags = {
    Name    = "${var.project}-peering"
    Project = "PeEx"
  }
}

# Routes on BOTH sides -- peering is not transitive and not automatic; without
# a route in each direction the connection exists but carries nothing.
resource "aws_route" "private_to_peer" {
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = var.peer_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main_to_peer.id
}

resource "aws_route" "public_to_peer" {
  route_table_id            = aws_route_table.public.id
  destination_cidr_block    = var.peer_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main_to_peer.id
}

resource "aws_route" "peer_to_main" {
  route_table_id            = aws_route_table.peer.id
  destination_cidr_block    = var.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main_to_peer.id
}

# --------------------------------------------------------- pre-shared secret
# Generated at apply time rather than written into the repo. It lands in
# Terraform state and in instance user-data, so it is demo-grade: for anything
# real, certificate authentication or AWS Secrets Manager belongs here instead.
resource "random_password" "ipsec_psk" {
  length  = 32
  special = false
}

# ------------------------------------------------------------- peer instance
resource "aws_security_group" "peer" {
  name        = "${var.project}-peer-sg"
  description = "Remote-network host: reachable only from the peered VPC"
  vpc_id      = aws_vpc.peer.id

  ingress {
    description = "IKE key exchange from the peered VPC"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "IPsec NAT traversal from the peered VPC"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "ESP: the encrypted payload itself"
    from_port   = 0
    to_port     = 0
    protocol    = "50"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "ICMP and SSH from the peered VPC, for connectivity testing"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "SSH from the peered VPC only -- no public path to this host"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "back to the peered VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "package installs (strongSwan) at boot"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "apt over plain HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-peer-sg"
    Project = "PeEx"
  }
}

# The peer host needs internet access once, to install strongSwan. It gets a
# public IP for that; the security group still admits nothing from outside.
resource "aws_internet_gateway" "peer" {
  vpc_id = aws_vpc.peer.id

  tags = {
    Name    = "${var.project}-peer-igw"
    Project = "PeEx"
  }
}

resource "aws_route" "peer_default" {
  route_table_id         = aws_route_table.peer.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.peer.id
}

resource "aws_instance" "peer" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.peer.id
  vpc_security_group_ids      = [aws_security_group.peer.id]
  key_name                    = aws_key_pair.peex.key_name
  private_ip                  = var.peer_host_ip
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"
  }

  user_data = templatefile("${path.module}/user-data/ipsec.sh.tpl", {
    local_ip  = var.peer_host_ip
    remote_ip = var.private_host_ip
    psk       = random_password.ipsec_psk.result
    side      = "peer"
  })
  user_data_replace_on_change = true

  tags = {
    Name    = "${var.project}-peer-host"
    Project = "PeEx"
    Role    = "remote-network"
  }
}
