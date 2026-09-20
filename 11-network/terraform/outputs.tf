output "vpc_id" {
  value = aws_vpc.main.id
}

output "web_public_ip" {
  value = aws_instance.web.public_ip
}

output "web_private_ip" {
  value = aws_instance.web.private_ip
}

output "monitoring_public_ip" {
  value = aws_instance.monitoring.public_ip
}

output "ssh_key_path" {
  value = local_sensitive_file.private_key.filename
}

output "ssh_web" {
  value = "ssh -i ${local_sensitive_file.private_key.filename} -o StrictHostKeyChecking=accept-new ubuntu@${aws_instance.web.public_ip}"
}

output "ssh_monitoring" {
  value = "ssh -i ${local_sensitive_file.private_key.filename} -o StrictHostKeyChecking=accept-new ubuntu@${aws_instance.monitoring.public_ip}"
}

output "web_url" {
  value = "http://${aws_instance.web.public_ip}/"
}

output "grafana_url" {
  value = "http://${aws_instance.monitoring.public_ip}:3000  (admin / peexdemo123 -- change after first login)"
}

output "prometheus_url" {
  value = "http://${aws_instance.monitoring.public_ip}:9090"
}

# Consumed by 06-containers/observability/terraform (CloudWatch alarms need
# instance IDs). Exported here so that stack can read this one's state
# read-only instead of duplicating resource definitions.
output "web_instance_id" {
  value = aws_instance.web.id
}

output "monitoring_instance_id" {
  value = aws_instance.monitoring.id
}

# --- network build outputs ---------------------------------------------------
output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "nat_instance_public_ip" {
  value = aws_instance.nat.public_ip
}

output "private_host_ip" {
  value = aws_instance.private.private_ip
}

output "peer_host_ip" {
  value = aws_instance.peer.private_ip
}

output "peer_host_public_ip" {
  value = aws_instance.peer.public_ip
}

output "peering_connection_id" {
  value = aws_vpc_peering_connection.main_to_peer.id
}

output "flow_log_group" {
  value = aws_cloudwatch_log_group.flow_logs.name
}

output "ssh_private_host" {
  description = "No public IP by design -- reach it by jumping through the web instance."
  value       = "ssh -J ubuntu@${aws_instance.web.public_ip} ubuntu@${aws_instance.private.private_ip}"
}
