# --- Network ACLs (subnet-level filtering) ----------------------------------
#
# WHY THESE EXIST ALONGSIDE SECURITY GROUPS
# Security groups are STATEFUL and attach to an instance: allow traffic in and
# the reply is allowed out automatically. NACLs are STATELESS and attach to a
# SUBNET: every direction must be allowed explicitly, which is why each list
# below carries an ephemeral-port rule for return traffic. Together they are
# defence in depth -- an instance with a mistakenly wide security group is
# still bounded by its subnet's NACL.
#
# Rule numbers are spaced by 10 so rules can be inserted later without
# renumbering. NACLs evaluate in ascending order and stop at the first match.

# ----------------------------------------------------------------- public tier
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.public.id, aws_subnet.public_b.id]

  tags = {
    Name    = "${var.project}-public-nacl"
    Tier    = "public"
    Project = "PeEx"
  }
}

# inbound: only the ports the workloads actually serve, from your IP only
resource "aws_network_acl_rule" "public_in_ssh" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.allowed_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "public_in_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.allowed_cidr
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "public_in_grafana" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.allowed_cidr
  from_port      = 3000
  to_port        = 3000
}

resource "aws_network_acl_rule" "public_in_prometheus" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 130
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.allowed_cidr
  from_port      = 9090
  to_port        = 9090
}

# traffic from inside the VPC (monitoring -> web:9100, NAT forwarding, etc.)
resource "aws_network_acl_rule" "public_in_vpc" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 140
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
}

# traffic arriving over the VPC peering link (peering.tf)
resource "aws_network_acl_rule" "public_in_peer" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 150
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.peer_vpc_cidr
}

# STATELESS: replies to connections the instances opened outbound (apt, docker
# pull) come back on ephemeral ports. Without this rule every outbound request
# would hang -- the classic NACL mistake.
resource "aws_network_acl_rule" "public_in_ephemeral" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 160
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "public_out_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

# ---------------------------------------------------------------- private tier
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private.id]

  tags = {
    Name    = "${var.project}-private-nacl"
    Tier    = "private"
    Project = "PeEx"
  }
}

# Inbound from inside the VPC only -- there is no rule admitting the internet,
# so even a wide-open security group could not expose an instance here.
resource "aws_network_acl_rule" "private_in_vpc" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
}

resource "aws_network_acl_rule" "private_in_peer" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.peer_vpc_cidr
}

# Return traffic for connections the private instance opened through the NAT
# instance (apt updates). Ephemeral ports only -- not a general inbound allow.
resource "aws_network_acl_rule" "private_in_ephemeral" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "private_out_all" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}
