
variable "aws_region" {
  description = "Région AWS de déploiement"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "Bloc CIDR du VPC principal"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_az_a_cidr" {
  description = "Subnet public AZ-a (Frontend A + NAT Gateway + EFS)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_az_b_cidr" {
  description = "Subnet public AZ-b (Frontend B si scaling + EFS)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_az_a_cidr" {
  description = "Subnet privé AZ-a (Streamer FFmpeg)"
  type        = string
  default     = "10.0.3.0/24"
}

variable "private_az_b_cidr" {
  description = "Subnet privé AZ-b (réservé, multi-AZ)"
  type        = string
  default     = "10.0.4.0/24"
}

variable "domain_name" {
  description = "Nom de domaine complet de l'application"
  type        = string
  default     = "julienralph-pod-1.devops.intuitivelabs.net"
}

variable "route53_zone_name" {
  description = "Zone Route53 parente du domaine"
  type        = string
  default     = "devops.intuitivelabs.net"
}

variable "alert_email" {
  description = "Email pour les alarmes CloudWatch"
  type        = string
  default     = "julien.sangongdjomo@telecom-paris.fr"
}

variable "ami_id" {
  description = "AMI Ubuntu 22.04 LTS us-east-1"
  type        = string
  default     = "ami-0261755bbcb8c4a84"
}

variable "instance_type_frontend" {
  description = "Type d'instance EC2 pour le Frontend (NGINX+RTMP)"
  type        = string
  default     = "t3.small"
}

variable "instance_type_streamer" {
  description = "Type d'instance EC2 pour le Streamer (FFmpeg)"
  type        = string
  default     = "t3.small"
}

variable "asg_desired" {
  description = "Nombre d'instances Frontend souhaité"
  type        = number
  default     = 1
}

variable "asg_min" {
  description = "Nombre minimum d'instances Frontend"
  type        = number
  default     = 1
}

variable "asg_max" {
  description = "Nombre maximum d'instances Frontend (scaling)"
  type        = number
  default     = 3
}
