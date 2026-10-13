variable "subscription_id" {
  description = "Consumer Azure subscription ID."
  type        = string
}

variable "tenant_id" {
  description = "Consumer Microsoft Entra tenant ID."
  type        = string
}

variable "private_link_service_id" {
  description = "Provider PLS resource ID returned by the provider stack."
  type        = string
}

variable "location" {
  description = "Must match the provider region while PLS Direct Connect is in preview."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Consumer resource group name."
  type        = string
  default     = "rg-plsdc-consumer"
}

variable "admin_username" {
  description = "Administrator username for the consumer VMSS."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "OpenSSH public key used by the consumer VMSS."
  type        = string
}

variable "vmss_sku" {
  description = "Consumer VMSS instance size. Standard_D2s_v5 is broadly available and supports Accelerated Networking."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "tags" {
  description = "Tags applied to consumer resources."
  type        = map(string)
  default = {
    architecture = "pls-direct-connect"
    side         = "consumer"
  }
}
