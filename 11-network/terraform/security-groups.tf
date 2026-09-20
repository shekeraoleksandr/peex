# --- Security groups (instance-level, stateful) ------------------------------
#
# Every rule below carries its business justification in `description`, which
# is what `describe-security-groups` prints -- so the justification travels
# with the rule instead of living only in this file.
#
# EGRESS IS NOT 0.0.0.0/0 ANYMORE. These instances need exactly three things
# outbound: package repositories and container registries (443, and 80 for
# apt), DNS, and each other. Everything else is denied, so a compromised
# container cannot open an arbitrary outbound channel.

locals {
  # Ports every instance legitimately needs outbound, with the reason.
  # Kept in one place so the three security groups cannot drift apart.
  common_egress = {
    https = { port = 443, protocol = "tcp", desc = "package repos, container registries, AWS APIs" }
    http  = { port = 80, protocol = "tcp", desc = "apt repositories that still use plain HTTP" }
    dns   = { port = 53, protocol = "udp", desc = "DNS resolution" }
  }
}

# --------------------------------------------------------------- web instance
resource "aws_security_group" "web" {
  name        = "${var.project}-web-sg"
  description = "Web/app instance: SSH+HTTP from allowed_cidr only; node_exporter only from the monitoring SG"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-web-sg"
    Tier    = "public"
    Project = "PeEx"
  }
}

resource "aws_security_group_rule" "web_in_ssh" {
  type              = "ingress"
  security_group_id = aws_security_group.web.id
  description       = "SSH for administration, from the operator IP only"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_cidr]
}

resource "aws_security_group_rule" "web_in_http" {
  type              = "ingress"
  security_group_id = aws_security_group.web.id
  description       = "nginx demo app, from the operator IP only (not public)"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_cidr]
}

# The metrics port is deliberately NOT open to allowed_cidr -- only the
# monitoring instance has any business scraping it.
resource "aws_security_group_rule" "web_in_node_exporter" {
  type                     = "ingress"
  security_group_id        = aws_security_group.web.id
  description              = "node_exporter scrape, from the monitoring instance only"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring.id
}

resource "aws_security_group_rule" "web_in_peer" {
  type              = "ingress"
  security_group_id = aws_security_group.web.id
  description       = "ICMP/SSH from the peered VPC over the private link"
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
  cidr_blocks       = [var.peer_vpc_cidr]
}

resource "aws_security_group_rule" "web_out" {
  for_each          = local.common_egress
  type              = "egress"
  security_group_id = aws_security_group.web.id
  description       = each.value.desc
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = each.value.protocol
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "web_out_vpc" {
  type              = "egress"
  security_group_id = aws_security_group.web.id
  description       = "internal traffic to other tiers in this VPC"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr, var.peer_vpc_cidr]
}

# -------------------------------------------------------- monitoring instance
resource "aws_security_group" "monitoring" {
  name        = "${var.project}-monitoring-sg"
  description = "Monitoring instance: SSH+Grafana+Prometheus from allowed_cidr only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-monitoring-sg"
    Tier    = "public"
    Project = "PeEx"
  }
}

resource "aws_security_group_rule" "mon_in_ssh" {
  type              = "ingress"
  security_group_id = aws_security_group.monitoring.id
  description       = "SSH for administration, from the operator IP only"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_cidr]
}

resource "aws_security_group_rule" "mon_in_grafana" {
  type              = "ingress"
  security_group_id = aws_security_group.monitoring.id
  description       = "Grafana UI, from the operator IP only"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_cidr]
}

resource "aws_security_group_rule" "mon_in_prometheus" {
  type              = "ingress"
  security_group_id = aws_security_group.monitoring.id
  description       = "Prometheus UI, from the operator IP only"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_cidr]
}

resource "aws_security_group_rule" "mon_out" {
  for_each          = local.common_egress
  type              = "egress"
  security_group_id = aws_security_group.monitoring.id
  description       = each.value.desc
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = each.value.protocol
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "mon_out_vpc" {
  type              = "egress"
  security_group_id = aws_security_group.monitoring.id
  description       = "scrape targets and peered network"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr, var.peer_vpc_cidr]
}

# ----------------------------------------------------------- private instance
resource "aws_security_group" "private" {
  name        = "${var.project}-private-sg"
  description = "Private-subnet workload: reachable only from inside the VPC, egress only via NAT"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-private-sg"
    Tier    = "private"
    Project = "PeEx"
  }
}

resource "aws_security_group_rule" "priv_in_vpc_ssh" {
  type              = "ingress"
  security_group_id = aws_security_group.private.id
  description       = "SSH from inside the VPC only -- there is no public path to this host"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
}

resource "aws_security_group_rule" "priv_in_icmp" {
  type              = "ingress"
  security_group_id = aws_security_group.private.id
  description       = "ICMP from the VPC and the peered network, for connectivity testing"
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
  cidr_blocks       = [var.vpc_cidr, var.peer_vpc_cidr]
}

resource "aws_security_group_rule" "priv_in_node_exporter" {
  type                     = "ingress"
  security_group_id        = aws_security_group.private.id
  description              = "node_exporter scrape, from the monitoring instance only"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.monitoring.id
}

resource "aws_security_group_rule" "priv_out" {
  for_each          = local.common_egress
  type              = "egress"
  security_group_id = aws_security_group.private.id
  description       = "${each.value.desc} (routed through the NAT instance)"
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = each.value.protocol
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "priv_out_vpc" {
  type              = "egress"
  security_group_id = aws_security_group.private.id
  description       = "internal traffic within the VPC and across the peering link"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  # peer_vpc_cidr was missing here originally: the private host could be
  # pinged FROM the peer network but could not send anything back, so every
  # main->peer test failed with 100% packet loss and no obvious cause.
  cidr_blocks = [var.vpc_cidr, var.peer_vpc_cidr]
}

# BUG 2: IPsec needs its own ports. Without these the tunnel can never come
# up, and traffic silently falls back to unencrypted -- which is exactly what
# tcpdump showed (plain ICMP echo instead of ESP).
resource "aws_security_group_rule" "priv_in_ike" {
  type              = "ingress"
  security_group_id = aws_security_group.private.id
  description       = "IKE key exchange from the peered network"
  from_port         = 500
  to_port           = 500
  protocol          = "udp"
  cidr_blocks       = [var.peer_vpc_cidr]
}

resource "aws_security_group_rule" "priv_in_ike_nat" {
  type              = "ingress"
  security_group_id = aws_security_group.private.id
  description       = "IPsec NAT traversal from the peered network"
  from_port         = 4500
  to_port           = 4500
  protocol          = "udp"
  cidr_blocks       = [var.peer_vpc_cidr]
}

resource "aws_security_group_rule" "priv_in_esp" {
  type              = "ingress"
  security_group_id = aws_security_group.private.id
  description       = "ESP: the encrypted payload itself"
  from_port         = 0
  to_port           = 0
  protocol          = "50"
  cidr_blocks       = [var.peer_vpc_cidr]
}
