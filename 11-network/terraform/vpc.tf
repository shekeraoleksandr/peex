# --- Network (VPC, subnets, routing) ---------------------------------------
#
# IP ADDRESSING PLAN (no overlap with the peer VPC in peering.tf, 10.43.0.0/16)
#
#   10.42.0.0/16    VPC "main"                        65536 addresses
#   ├─ 10.42.1.0/24   public-a   (AZ a)  web, monitoring, NAT instance
#   ├─ 10.42.2.0/24   public-b   (AZ b)  reserved — lets the stack grow to
#   │                                     multi-AZ without re-addressing
#   └─ 10.42.10.0/24  private-a  (AZ a)  no route to the IGW; egress via NAT
#
# The /24s leave 10.42.3-9 and 10.42.11+ free, so new tiers (db, cache) can be
# added later without touching anything that exists.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project}-vpc"
    Project     = "PeEx"
    Competency  = "network"
    Environment = "demo"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-igw"
    Project = "PeEx"
  }
}

# ---------------------------------------------------------------- public tier
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project}-public-a"
    Tier    = "public"
    Project = "PeEx"
  }
}

# Second AZ: nothing runs here yet. It exists so the design satisfies
# "supports scalability and future expansion without rearchitecting" --
# adding an ALB or a second instance later needs no new address planning.
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_b_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project}-public-b"
    Tier    = "public"
    Project = "PeEx"
  }
}

# NOTE: no inline `route` blocks anywhere in this file, deliberately.
# An aws_route_table with inline route blocks is AUTHORITATIVE: every apply
# resets the table to exactly those routes and silently deletes any route
# added by a separate aws_route resource. Mixing the two cost us the peering
# routes -- Terraform state listed aws_route.private_to_peer as created while
# AWS had no such route, so traffic left the peer VPC and never came back.
# Every route is a standalone aws_route resource now.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-public-rt"
    Tier    = "public"
    Project = "PeEx"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# --------------------------------------------------------------- private tier
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false # what actually makes this subnet private

  tags = {
    Name    = "${var.project}-private-a"
    Tier    = "private"
    Project = "PeEx"
  }
}

# The private route table has NO route to the internet gateway. Outbound goes
# through the NAT instance (nat.tf); inbound from the internet is therefore
# impossible regardless of security-group rules. Internal traffic between
# subnets works via the implicit VPC-local route.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-private-rt"
    Tier    = "private"
    Project = "PeEx"
  }
}

# Outbound through the NAT instance -- see the note above for why this is a
# standalone resource rather than an inline block.
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# --------------------------------------------------- private access to S3
# Gateway endpoint: traffic from the VPC to S3 stays on the AWS network
# instead of going out through the NAT instance and across the internet.
# Gateway endpoints are free, unlike interface endpoints.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private.id,
    aws_route_table.public.id,
  ]

  tags = {
    Name    = "${var.project}-s3-endpoint"
    Project = "PeEx"
  }
}
