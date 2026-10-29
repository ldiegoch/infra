terraform {
  # Estado remoto en Cloudflare R2 (API compatible con S3). El endpoint no
  # se escribe aquí: lo aporta el CI con la variable de entorno
  # AWS_ENDPOINT_URL_S3. El bloqueo usa un archivo .tflock en el bucket.
  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "platform/terraform.tfstate"
    region                      = "auto"
    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  # Cifrado obligatorio del estado y de los planes guardados. La frase llega
  # como variable sensible desde el CI (TF_VAR_state_passphrase).
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }

    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }

    state {
      method   = method.aes_gcm.main
      enforced = true
    }

    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}
