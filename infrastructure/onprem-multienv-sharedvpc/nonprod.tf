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

###############################################################################
#                                   Projects                                  #
###############################################################################

module "nonprod-host" {
  source          = "../../modules/project"
  name            = "nonprod-host"
  parent          = var.root_node
  prefix          = var.prefix
  billing_account = var.billing_account_id
  services        = var.project_services
}

module "nonprod-service-1" {
  source          = "../../modules/project"
  name            = "nonprod-1"
  parent          = var.root_node
  prefix          = var.prefix
  billing_account = var.billing_account_id
  services        = var.project_services
}

###############################################################################
#                                     VPC                                     #
###############################################################################

module "nonprod-vpc" {
  source          = "../../modules/net-vpc"
  project_id      = module.nonprod-host.project_id
  name            = "shared-vpc"
  shared_vpc_host = true
  shared_vpc_service_projects = [
    module.nonprod-service-1.project_id,
  ]
  subnets = [
    {
      ip_cidr_range      = var.ip_ranges.nonprod
      name               = "nonprod"
      region             = var.region
      secondary_ip_range = {}
    }
  ]
  iam_roles = {
    "${var.region}/nonprod" = ["roles/compute.networkUser"]
  }
}

module "nonprod-firewall" {
  source               = "../../modules/net-vpc-firewall"
  project_id           = module.nonprod-host.project_id
  network              = module.nonprod-vpc.name
  admin_ranges_enabled = true
  admin_ranges         = values(var.ip_ranges)
}

###############################################################################
#                                     VPN                                     #
###############################################################################

module "nonprod-vpn-to-landing" {
  source     = "../../modules/net-vpn-dynamic"
  project_id = module.nonprod-host.project_id
  region     = var.region
  network    = module.nonprod-vpc.name
  name       = "nonprod-to-landing"
  router_asn = var.bgp_asn.nonprod
  tunnels = {
    hub = {
      bgp_peer = {
        address = local.bgp_interfaces.landing-nonprod
        asn     = var.bgp_asn.landing
      }
      bgp_peer_options  = null
      bgp_session_range = "${local.bgp_interfaces.nonprod}/30"
      ike_version       = 2
      peer_ip           = module.landing-vpn-to-nonprod.address
      shared_secret     = module.landing-vpn-to-nonprod.random_secret
    }
  }
}

###############################################################################
#                                   Services                                  #
###############################################################################

module "nonprod-p1-vm" {
  source     = "../../modules/compute-vm"
  project_id = module.nonprod-service-1.project_id
  region     = var.region
  zone       = "${var.region}-b"
  name       = "test"
  network_interfaces = [{
    network    = module.nonprod-vpc.self_link,
    subnetwork = module.nonprod-vpc.subnet_self_links["${var.region}/nonprod"],
    nat        = false,
    addresses  = null
  }]
  instance_count = 1
  tags           = ["ssh"]
  metadata = {
    startup-script = join("\n", [
      "#! /bin/bash",
      "apt-get update",
      "apt-get install -y bash-completion kubectl dnsutils"
    ])
  }
  service_account_create = true
}
