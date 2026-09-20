# --- VPC Flow Logs (traffic monitoring) --------------------------------------
#
# Records ACCEPT and REJECT decisions for every flow in the VPC. This is what
# makes "denied traffic is blocked as expected" verifiable after the fact
# instead of only at the moment someone runs a curl: a REJECT record names the
# source, destination, port and protocol that was dropped.
#
# Cost control: a 1-day retention on the log group. Flow logs on a busy VPC get
# expensive fast, and this is a demo network.

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.project}-flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = {
    Name    = "${var.project}-flow-logs"
    Project = "PeEx"
  }
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.project}-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json

  tags = {
    Project = "PeEx"
  }
}

# Scoped to this one log group rather than "*" -- least privilege applies to
# the observability plumbing too.
data "aws_iam_policy_document" "flow_logs_write" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "${var.project}-flow-logs-policy"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_write.json
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL" # ACCEPT and REJECT both, so denials are auditable
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  tags = {
    Name    = "${var.project}-flow-log"
    Project = "PeEx"
  }
}
