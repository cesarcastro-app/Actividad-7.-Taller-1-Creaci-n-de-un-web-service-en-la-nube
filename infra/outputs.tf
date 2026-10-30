output "application_url" {
  description = "URL pública del servicio después de ejecutar scripts/deploy.ps1."
  value       = "http://${aws_eip.app.public_ip}"
}

output "public_ip" {
  description = "Dirección IPv4 elástica de la instancia."
  value       = aws_eip.app.public_ip
}

output "instance_id" {
  description = "Identificador usado por AWS Systems Manager."
  value       = aws_instance.app.id
}

output "ecr_repository_url" {
  description = "Repositorio privado donde se publican las imágenes."
  value       = aws_ecr_repository.app.repository_url
}

output "aws_region" {
  value = var.aws_region
}
