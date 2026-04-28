variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD Tenant ID"
  type        = string
}

variable "client_id" {
  description = "Azure User Managed Identity Client ID"
  type        = string
}

variable "resource_group_name" {
  description = "기존 리소스 그룹 이름"
  type        = string
  default     = "AZ-WORKING-RG"
}

variable "location" {
  description = "Azure 리전"
  type        = string
  default     = "koreacentral"
}

variable "vnet_name" {
  description = "Virtual Network 이름"
  type        = string
  default     = "vnet-oidc-test"
}
