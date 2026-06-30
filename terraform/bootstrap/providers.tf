# The bootstrap stack runs ONCE, locally, with administrator credentials. It has
# no remote backend (it creates the backend), so its state is local — keep
# bootstrap/terraform.tfstate safe or re-import if lost.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Component = "bootstrap"
    }
  }
}
