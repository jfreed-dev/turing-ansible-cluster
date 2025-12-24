terraform {
  required_providers {
    turingpi = {
      source  = "jfreed-dev/turingpi"
      version = ">= 1.0.10"
    }
  }
}

variable "nodes" {
  description = "Map of nodes to provision"
  type = map(object({
    node          = number
    power_state   = optional(string, "on")
    firmware_file = optional(string, null)
    boot_check    = optional(bool, true)
    boot_pattern  = optional(string, "login:")
    boot_timeout  = optional(number, 300)
  }))
}

variable "flash_enabled" {
  description = "Enable firmware flashing (set false to skip)"
  type        = bool
  default     = false
}

resource "turingpi_node" "nodes" {
  for_each = var.nodes

  node                 = each.value.node
  power_state          = each.value.power_state
  firmware_file        = var.flash_enabled ? each.value.firmware_file : null
  boot_check           = each.value.boot_check
  boot_check_pattern   = each.value.boot_pattern
  login_prompt_timeout = each.value.boot_timeout
}

output "node_status" {
  description = "Power state of each node"
  value = {
    for k, v in turingpi_node.nodes : k => {
      node        = v.node
      power_state = v.power_state
      flashed     = v.firmware_file != null
    }
  }
}

output "all_nodes_ready" {
  description = "True if all nodes are powered on"
  value       = alltrue([for n in turingpi_node.nodes : n.power_state == "on"])
}
