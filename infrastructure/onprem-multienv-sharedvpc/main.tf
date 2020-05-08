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

locals {
  bgp_interfaces = {
    landing-onprem  = "${cidrhost(var.bgp_interface_ranges.onprem, 1)}"
    landing-nonprod = "${cidrhost(var.bgp_interface_ranges.nonprod, 1)}"
    landing-prod    = "${cidrhost(var.bgp_interface_ranges.prod, 1)}"
    nonprod         = "${cidrhost(var.bgp_interface_ranges.nonprod, 2)}"
    onprem          = "${cidrhost(var.bgp_interface_ranges.onprem, 2)}"
    prod            = "${cidrhost(var.bgp_interface_ranges.prod, 2)}"
  }
  netblocks = {
    dns        = data.google_netblock_ip_ranges.dns-forwarders.cidr_blocks_ipv4.0
    private    = data.google_netblock_ip_ranges.private-googleapis.cidr_blocks_ipv4.0
    restricted = data.google_netblock_ip_ranges.restricted-googleapis.cidr_blocks_ipv4.0
  }
  vips = {
    private    = [for i in range(4) : cidrhost(local.netblocks.private, i)]
    restricted = [for i in range(4) : cidrhost(local.netblocks.restricted, i)]
  }
  vm-startup-script = join("\n", [
    "#! /bin/bash",
    "apt-get update && apt-get install -y bash-completion dnsutils kubectl"
  ])
}

data "google_netblock_ip_ranges" "dns-forwarders" {
  range_type = "dns-forwarders"
}

data "google_netblock_ip_ranges" "private-googleapis" {
  range_type = "private-googleapis"
}

data "google_netblock_ip_ranges" "restricted-googleapis" {
  range_type = "restricted-googleapis"
}

###############################################################################
#                                   Projects                                  #
###############################################################################

module "onprem-project" {
  source          = "../../modules/project"
  name            = "onprem"
  parent          = var.root_node
  prefix          = var.prefix
  billing_account = var.billing_account_id
  services        = var.project_services
  oslogin         = true
}

###############################################################################
#                                     VPC                                     #
###############################################################################

module "vpc-onprem" {
  source     = "../../modules/net-vpc"
  project_id = module.onprem-project.project_id
  name       = "to-onprem"
  subnets = [
    {
      ip_cidr_range      = var.ip_ranges.onprem_project
      name               = "subnet"
      region             = var.region
      secondary_ip_range = {}
    }
  ]
}

module "vpc-onprem-firewall" {
  source               = "../../modules/net-vpc-firewall"
  project_id           = module.onprem-project.project_id
  network              = module.vpc-onprem.name
  admin_ranges_enabled = true
  admin_ranges         = values(var.ip_ranges)
  ssh_source_ranges    = var.ssh_source_ranges
}

###############################################################################
#                                     VPN                                     #
###############################################################################

module "config-onprem" {
  source              = "../../modules/cloud-config-container/onprem"
  config_variables    = { dns_forwarder_address = var.dns_forwarder_address }
  coredns_config      = "assets/Corefile"
  local_ip_cidr_range = var.ip_ranges.onprem
  vpn_config = {
    peer_ip       = module.landing-vpn-to-onprem.address
    shared_secret = module.landing-vpn-to-onprem.random_secret
    type          = "dynamic"
  }
  vpn_dynamic_config = {
    local_bgp_asn     = var.bgp_asn.onprem
    local_bgp_address = local.bgp_interfaces.onprem
    peer_bgp_asn      = var.bgp_asn.landing
    peer_bgp_address  = local.bgp_interfaces.landing-onprem
  }
}

###############################################################################
#                                   Services                                  #
###############################################################################

module "service-account-onprem" {
  source     = "../../modules/iam-service-accounts"
  project_id = module.onprem-project.project_id
  names      = ["gce-onprem"]
  iam_project_roles = {
    (module.onprem-project.project_id) = [
      "roles/compute.viewer",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
    ]
  }
}

module "vm-onprem" {
  source        = "../../modules/compute-vm"
  project_id    = module.onprem-project.project_id
  region        = var.region
  zone          = "${var.region}-b"
  instance_type = "f1-micro"
  name          = "onprem"
  boot_disk = {
    image = "ubuntu-os-cloud/ubuntu-1804-lts"
    type  = "pd-ssd"
    size  = 10
  }
  metadata = {
    user-data = module.config-onprem.cloud_config
  }
  network_interfaces = [{
    network    = module.vpc-onprem.name
    subnetwork = module.vpc-onprem.subnet_self_links["${var.region}/subnet"]
    nat        = true,
    addresses  = null
  }]
  service_account        = module.service-account-onprem.email
  service_account_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  tags                   = ["ssh"]
}
