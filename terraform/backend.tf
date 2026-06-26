terraform {
  backend "s3" {
    bucket         = "terraform-backend-bucket-085960855786"
    key            = "eks-vpc/terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    use_lockfile   = true
  }
}
