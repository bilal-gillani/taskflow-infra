variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "location" {
  description = "Azure Region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group Name"
  type        = string
}

variable "address_space" {
  description = "Address space for VNet"
  type        = list(string)
}

variable "subnets" {
  description = "Map of subnets to create with name suffix and address prefixes"
  type = map(object({
    address_prefixes = list(string)
  }))
}

variable "enable_nsg_association" {
  type    = bool
  default = true
}

variable "nsg_id" {
  description = "Optional NSG ID to attach to subnets"
  type        = string
  default     = null
}
