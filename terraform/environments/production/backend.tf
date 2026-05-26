terraform {
  backend "s3" {
    bucket       = "ecommerce-platform-terraform-state"
    key          = "production/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
