terraform {
  required_version = ">= 1.5"

  required_providers {
    turingpi = {
      source  = "jfreed-dev/turingpi"
      version = ">= 1.0.10"
    }
  }
}

# Provider configured via environment variables:
# TURINGPI_USERNAME, TURINGPI_PASSWORD, TURINGPI_ENDPOINT, TURINGPI_INSECURE
provider "turingpi" {}

variable "firmware_path" {
  description = "Path to Ubuntu/Armbian firmware image for RK1"
  type        = string
  default     = ""
}

variable "flash_nodes" {
  description = "Enable firmware flashing (destructive!)"
  type        = bool
  default     = false
}

variable "boot_pattern" {
  description = "UART pattern to detect successful boot"
  type        = string
  default     = "login:" # Ubuntu/Armbian default
}

variable "boot_timeout" {
  description = "Seconds to wait for boot completion"
  type        = number
  default     = 300 # 5 minutes for flash + boot
}

locals {
  # Node configuration matching existing Talos setup
  nodes = {
    "turing-cp1" = {
      node          = 1
      power_state   = "on"
      firmware_file = var.firmware_path != "" ? var.firmware_path : null
      boot_check    = true
      boot_pattern  = var.boot_pattern
      boot_timeout  = var.boot_timeout
    }
    "turing-w1" = {
      node          = 2
      power_state   = "on"
      firmware_file = var.firmware_path != "" ? var.firmware_path : null
      boot_check    = true
      boot_pattern  = var.boot_pattern
      boot_timeout  = var.boot_timeout
    }
    "turing-w2" = {
      node          = 3
      power_state   = "on"
      firmware_file = var.firmware_path != "" ? var.firmware_path : null
      boot_check    = true
      boot_pattern  = var.boot_pattern
      boot_timeout  = var.boot_timeout
    }
    "turing-w3" = {
      node          = 4
      power_state   = "on"
      firmware_file = var.firmware_path != "" ? var.firmware_path : null
      boot_check    = true
      boot_pattern  = var.boot_pattern
      boot_timeout  = var.boot_timeout
    }
  }
}

module "bmc" {
  source = "../../modules/bmc"

  nodes         = local.nodes
  flash_enabled = var.flash_nodes
}

output "cluster_status" {
  description = "Status of all cluster nodes"
  value       = module.bmc.node_status
}

output "cluster_ready" {
  description = "True when all nodes are booted and ready"
  value       = module.bmc.all_nodes_ready
}

output "next_steps" {
  description = "Instructions for next steps"
  value       = module.bmc.all_nodes_ready ? "All nodes are ready! Next: cd ../../ansible && ansible-playbook -i inventories/server/hosts.yml playbooks/site.yml" : "Waiting for nodes to boot..."
}
