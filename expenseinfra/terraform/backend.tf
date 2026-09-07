# GitLab managed Terraform state (HTTP backend).
# All settings are supplied at `terraform init` time (CI: see .gitlab-ci.yml).
# Local: use GitLab UI → Terraform states → "Copy Terraform init command", or:
#   terraform init -backend-config=path/to/your.gitlab.backend.hcl
# Do not commit tokens; use CI_JOB_TOKEN in pipelines or a personal token locally.

#terraform {
#  backend "http" {}
#}

terraform {
  backend "s3" {
    bucket         = "<your-terraform-state-bucket>" # bucket name
    key            = "prod/terraform.tfstate"      # state file in bucket directory
    region         = "ca-central-1"                # region
    dynamodb_table = "<your-terraform-locks-table>" # state lock table (created manually, lives outside this project)
    encrypt        = true                          # encrypt state at rest
  }
}
