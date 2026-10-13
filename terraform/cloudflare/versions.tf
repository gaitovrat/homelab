terraform {
  # OpenTofu (from the dev shell) or Terraform; the S3 backend's use_lockfile needs
  # OpenTofu >= 1.10 or Terraform >= 1.11.
  required_version = ">= 1.10"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.27.0"
    }
  }

  # State in Cloudflare R2 through its S3 API. The bucket and its access key are created
  # by hand once (see README). The endpoint (https://<account_id>.r2.cloudflarestorage.com)
  # and the key come from AWS_ENDPOINT_URL_S3, AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY,
  # which tofu.sh sets from 1Password.
  backend "s3" {
    bucket       = "homelab-tfstate"
    key          = "cloudflare/terraform.tfstate"
    region       = "auto"
    use_lockfile = true

    # R2 isn't AWS: no STS, IMDS, regions or checksums.
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}

# Reads CLOUDFLARE_API_TOKEN.
provider "cloudflare" {}
