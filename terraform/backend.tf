# Stockage état Terraform
terraform {
  backend "s3" {
    bucket       = "gin208-tfstate-ralph"    # Bucket créé par bootstrap.sh
    key          = "gin208/terraform.tfstate" # Chemin du fichier d'état dans le bucket
    region       = "us-east-1"
    use_lockfile = true                       # Verrou natif S3 (remplace dynamodb_table déprécié)
    encrypt      = true                       # Chiffre le tfstate au repos
  }
}
