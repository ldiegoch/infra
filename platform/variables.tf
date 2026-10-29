variable "state_passphrase" {
  type        = string
  description = "Frase para cifrar el estado y los planes de OpenTofu. La proporciona el CI; nunca se escribe en el repositorio."
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "La frase de cifrado del estado debe tener al menos 16 caracteres."
  }
}
