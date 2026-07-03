# ============================================================
# SSH - Acces temporaire pour Ansible (en attendant SSM/IAM)
# ============================================================
# Approche cible : SSM Session Manager (zero port 22, acces tracable via CloudTrail).
# Approche actuelle : SSH avec cle Ed25519, active sur instruction du professeur
# en attendant le deblocage des permissions IAM dans le compte SSO.
#
# A supprimer une fois les roles IAM accordes et SSM fonctionnel.
# ============================================================

# La cle publique est lue depuis le fichier local genere par ssh-keygen.
# pathexpand() resout le ~ vers le home directory reel de l'utilisateur.
resource "aws_key_pair" "gin208" {
  key_name   = "gin208-key"
  public_key = file(pathexpand("~/.ssh/gin208-key.pub"))

  tags = {
    Name = "${local.name_prefix}-keypair"
  }
}

# Port 22 ingress sur le SG Streamer
# Le Streamer est dans un subnet public donc accessible via SSH depuis Internet.
resource "aws_security_group_rule" "streamer_ingress_ssh" {
  security_group_id = aws_security_group.streamer.id
  type              = "ingress"
  description       = "SSH temporaire pour execution Ansible"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Port 22 ingress sur le SG Frontend
# Les instances Frontend (ASG) sont dans les subnets publics.
resource "aws_security_group_rule" "frontend_ingress_ssh" {
  security_group_id = aws_security_group.frontend.id
  type              = "ingress"
  description       = "SSH temporaire pour execution Ansible"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}
