variable "subscription_id" {
  description = "Service-provider Azure subscription ID."
  type        = string
}

variable "tenant_id" {
  description = "Service-provider Microsoft Entra tenant ID."
  type        = string
}

variable "consumer_subscription_id" {
  description = "Consumer subscription allowed to discover this Private Link Service."
  type        = string
}

variable "location" {
  description = "Azure region. PLS Direct Connect preview requires all participating resources in the same supported region."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Provider resource group name."
  type        = string
  default     = "rg-plsdc-provider"
}

variable "admin_username" {
  description = "Administrator username for the provider VMSS."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "OpenSSH public key used by the provider VMSS."
  type        = string
}

variable "vmss_sku" {
  description = "Provider VMSS instance size. Standard_D2s_v5 is broadly available and supports Accelerated Networking."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "tls_certificate_pfx_base64" {
  description = "Base64-encoded PFX certificate for the Application Gateway HTTPS listener."
  type        = string
  sensitive   = true
}

variable "tls_certificate_password" {
  description = "Password for the Application Gateway PFX certificate."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to provider resources."
  type        = map(string)
  default = {
    architecture = "pls-direct-connect"
    side         = "provider"
  }
}
