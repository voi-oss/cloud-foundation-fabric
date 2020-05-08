/**
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

variable "bgp_asn" {
  description = "BGP ASNs."
  type        = map(number)
  default = {
    landing = 64513
    onprem  = 64514
    prod    = 64515
    nonprod = 64516
  }
}

variable "bgp_interface_ranges" {
  description = "BGP interface IP CIDR ranges."
  type        = map(string)
  default = {
    onprem  = "169.254.1.0/30"
    prod    = "169.254.1.4/30"
    nonprod = "169.254.1.8/30"
  }
}

variable "billing_account_id" {
  description = "Billing account id used as to create projects."
  type        = string
}

variable "dns_forwarder_address" {
  description = "Address of the DNS server used to forward queries from on-premises."
  type        = string
  default     = "10.0.0.2"
}

variable "ip_ranges" {
  description = "IP CIDR ranges."
  type        = map(string)
  default = {
    landing        = "10.0.0.0/24"
    onprem         = "10.0.16.0/24"
    onprem_project = "10.0.32.0/24"
    prod           = "10.0.48.0/24"
    nonprod        = "10.0.64.0/24"
  }
}

variable "prefix" {
  description = "Prefix used for resources that need unique names."
  type        = string
}

variable "project_services" {
  description = "Service APIs enabled by default in new projects."
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "dns.googleapis.com",
  ]
}

variable "region" {
  description = "VPC region."
  type        = string
  default     = "europe-west1"
}

variable "root_node" {
  description = "Root node for the new hierarchy, either 'organizations/org_id' or 'folders/folder_id'."
  type        = string
}

variable "forwarder_address" {
  description = "GCP DNS inbound policy forwarder address."
  type        = string
  default     = "10.0.0.2"
}

variable "ssh_source_ranges" {
  description = "IP CIDR ranges that will be allowed to connect via SSH to the onprem instance."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

