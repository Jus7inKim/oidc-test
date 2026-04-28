terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

# ============================================================
# AzureRM Provider - OIDC 인증 설정
# ARM_USE_OIDC=true 환경변수를 참조하여 OIDC 토큰으로 인증
# ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID 환경변수 참조
# ============================================================
provider "azurerm" {
  features {}

  use_oidc        = true
  client_id       = var.client_id
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id

  # UAMI는 구독 레벨 Resource Provider 등록 권한 없음 → 자동 등록 비활성화
  resource_provider_registrations = "none"
}

# ============================================================
# 리소스 그룹 데이터 소스 (기존 RG 참조)
# ============================================================
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

# ============================================================
# VNet 생성
# ============================================================
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "test"
    managed_by  = "terraform"
    deployed_by = "github-actions-oidc"
  }
}

# ============================================================
# 서브넷 생성
# ============================================================
resource "azurerm_subnet" "subnet_default" {
  name                 = "snet-default"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "subnet_app" {
  name                 = "snet-app"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}
