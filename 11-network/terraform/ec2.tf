# --- Compute (EC2 instances) ------------------------------------------------

# Generated locally so the demo is fully self-contained -- no pre-existing
# key pair required. The private key is written to disk (0600) and git-ignored.
resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "peex" {
  key_name   = "${var.project}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  filename        = "${path.module}/peex-netcompute-key.pem"
  content         = tls_private_key.ssh.private_key_openssh
  file_permission = "0600"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# The demo app: nginx + node_exporter. node_exporter is the thing Prometheus
# scrapes over the private VPC IP -- it is never exposed publicly (see the
# security-group rule in security-groups.tf).
resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.peex.key_name
  private_ip             = var.web_host_ip

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  user_data = file("${path.module}/user-data/web.sh")

  # Without this the provider only rewrites the stored user_data attribute
  # in place -- the instance keeps running and cloud-init never re-runs, so
  # a fixed boot script would silently have no effect.
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project}-web"
  }
}

# Monitoring: Prometheus + Grafana in Docker, scraping the web instance's
# node_exporter over its private IP -- real hosted observability, not a local
# docker-compose stack on your laptop.
resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  key_name               = aws_key_pair.peex.key_name

  metadata_options {
    http_tokens = "required"
  }

  user_data = templatefile("${path.module}/user-data/monitoring.sh.tpl", {
    web_private_ip = aws_instance.web.private_ip
  })

  user_data_replace_on_change = true

  tags = {
    Name = "${var.project}-monitoring"
  }
}

# Private-subnet workload. No public IP, no route to the internet gateway --
# reachable only from inside the VPC or over the peering link, and its outbound
# traffic leaves through the NAT instance. This is the host that proves the
# private subnet actually behaves like one.
resource "aws_instance" "private" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.private.id]
  key_name               = aws_key_pair.peex.key_name
  private_ip             = var.private_host_ip

  metadata_options {
    http_tokens = "required"
  }

  # Same IPsec endpoint script as the peer host, with the addresses swapped.
  user_data = templatefile("${path.module}/user-data/ipsec.sh.tpl", {
    local_ip  = var.private_host_ip
    remote_ip = var.peer_host_ip
    psk       = random_password.ipsec_psk.result
    side      = "main-private"
  })
  user_data_replace_on_change = true

  # Without the NAT route in place first, apt in user-data has no egress.
  depends_on = [aws_route_table_association.private]

  tags = {
    Name    = "${var.project}-private-host"
    Tier    = "private"
    Project = "PeEx"
  }
}
