output "vnet_id" {
  description = "생성된 VNet의 ID"
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "생성된 VNet 이름"
  value       = azurerm_virtual_network.vnet.name
}

output "vnet_address_space" {
  description = "VNet 주소 공간"
  value       = azurerm_virtual_network.vnet.address_space
}

output "subnet_default_id" {
  description = "기본 서브넷 ID"
  value       = azurerm_subnet.subnet_default.id
}

output "subnet_app_id" {
  description = "앱 서브넷 ID"
  value       = azurerm_subnet.subnet_app.id
}
