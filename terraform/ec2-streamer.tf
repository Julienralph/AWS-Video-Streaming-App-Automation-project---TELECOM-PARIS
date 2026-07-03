# ============================================================
# EC2 - Streamer (FFmpeg)
# ============================================================
#
# Décisions clés :
# - Subnet public (temporaire) : NAT GW desactive, quota EIP atteint
# - SSH via cle Ed25519 (temporaire) : SSM desactive, acces Ansible sur instruction du prof
# - user_data = bootstrap minimal, FFmpeg installe par Ansible

resource "aws_instance" "streamer" {
  ami                    = var.ami_id
  instance_type          = var.instance_type_streamer
  subnet_id              = aws_subnet.public_az_a.id # Temporaire : NAT GW desactive (quota EIP atteint)
  vpc_security_group_ids = [aws_security_group.streamer.id]
  key_name               = aws_key_pair.gin208.key_name # Temporaire : SSH en attendant SSM/IAM
  # iam_instance_profile = aws_iam_instance_profile.streamer.name  # desactive : iam:CreateRole non autorise

  # Sans instance profile, SSM Session Manager n'est pas disponible sur cette instance.

  # disque racine =20 Go .
  # Les segments vidéo ne sont PAS stockés ici (pas d'EFS sur le Streamer).
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  # Bootstrap minimal : démarre SSM agent + installe CloudWatch agent.
  # templatefile() lit le fichier .tpl et substitue les variables ${...}.
 
  user_data = templatefile("${path.module}/templates/streamer_user_data.sh.tpl", {})

  # depends_on = [aws_iam_instance_profile.streamer]  # desactive avec le bloc IAM

  tags = {
    Name = "${local.name_prefix}-streamer"
    Role = "streamer"
  }
}
