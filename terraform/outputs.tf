output "vpc_id" {
  description = "ID du VPC"
  value       = aws_vpc.main.id
}

output "alb_dns" {
  description = "DNS du Load Balancer"
  value       = aws_lb.main.dns_name
}

output "cloudfront_domain" {
  description = "Domaine CloudFront genere par AWS"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "app_url" {
  description = "URL finale de l application"
  value       = "https://${var.domain_name}"
}

output "efs_id" {
  description = "ID du systeme de fichiers EFS partage"
  value       = aws_efs_file_system.main.id
}

output "streamer_instance_id" {
  description = "ID de l instance Streamer pour SSM Session Manager"
  value       = aws_instance.streamer.id
}

output "frontend_asg_name" {
  description = "Nom du Auto Scaling Group Frontend"
  value       = aws_autoscaling_group.frontend.name
}

output "s3_player_bucket" {
  description = "Nom du bucket S3 player HTML"
  value       = aws_s3_bucket.player.bucket
}
