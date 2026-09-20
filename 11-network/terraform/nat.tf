# --- NAT instance (outbound access for the private subnet) ------------------
#
# A managed NAT Gateway costs ~$32/month whether or not it moves a byte. A
# t3.micro NAT instance does the same job here for ~$7.50/month (or nothing,
# inside the free tier) and makes the mechanism visible: disable the source/
# destination check so the instance may forward packets it is not addressed to,
# turn on ip_forward, and MASQUERADE outbound traffic behind its own IP.

resource "aws_security_group" "nat" {
  name        = "${var.project}-nat-sg"
  description = "NAT instance: accepts traffic from the private subnet, forwards it out"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "any traffic originating in the private subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.private_subnet_cidr]
  }

  ingress {
    description = "SSH from your IP only (troubleshooting)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    description = "forwarded traffic on to the internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-nat-sg"
    Project = "PeEx"
  }
}

resource "aws_instance" "nat" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.nat.id]
  key_name               = aws_key_pair.peex.key_name

  # THE critical setting. EC2 normally drops packets whose destination is not
  # the instance itself; a NAT box exists precisely to forward those, so the
  # check must be off. Forget this and the private subnet has no egress and no
  # error message explaining why.
  source_dest_check = false

  metadata_options {
    http_tokens = "required"
  }

  user_data                   = file("${path.module}/user-data/nat.sh")
  user_data_replace_on_change = true

  tags = {
    Name    = "${var.project}-nat"
    Tier    = "public"
    Role    = "nat"
    Project = "PeEx"
  }
}
