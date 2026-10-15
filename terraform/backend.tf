# El estado remoto se configura al hacer init (ver README), para no
# hardcodear nombres de bucket en el repositorio:
#
#   terraform init \
#     -backend-config="bucket=<BUCKET>" \
#     -backend-config="key=pf-devops/<ENV>/terraform.tfstate" \
#     -backend-config="region=<REGION>" \
#     -backend-config="dynamodb_table=<LOCK_TABLE>"
terraform {
  backend "s3" {
    encrypt = true
  }
}
