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

module "landing-host" {
  source          = "../../modules/project"
  name            = "landing"
  parent          = var.root_node
  prefix          = var.prefix
  billing_account = var.billing_account_id
  services        = var.project_services
}

###############################################################################
#                                     VPC                                     #
###############################################################################

module "landing-vpc" {
  source     = "../../modules/net-vpc"
  project_id = module.landing-host.project_id
  name       = "landing"
  subnets = [
    {
      ip_cidr_range      = var.ip_ranges.landing
      name               = "landing"
      region             = var.region
      secondary_ip_range = {}
    }
  ]
}

module "landing-vpc-firewall" {
  source               = "../../modules/net-vpc-firewall"
  project_id           = module.landing-host.project_id
  network              = module.landing-vpc.name
  admin_ranges_enabled = true
  admin_ranges         = values(var.ip_ranges)
  ssh_source_ranges    = var.ssh_source_ranges
}

module "landing-nat" {
  source        = "../../modules/net-cloudnat"
  project_id    = module.landing-host.project_id
  region        = var.region
  name          = "default"
  router_create = false
  router_name   = module.landing-vpn-to-onprem.router_name
}

###############################################################################
#                                     VPN                                     #
###############################################################################

module "landing-vpn-to-onprem" {
  source     = "../../modules/net-vpn-dynamic"
  project_id = module.landing-host.project_id
  region     = module.landing-vpc.subnet_regions["${var.region}/landing"]
  network    = module.landing-vpc.name
  name       = "landing-to-onprem"
  router_asn = var.bgp_asn.landing
  tunnels = {
    onprem = {
      bgp_peer = {
        address = local.bgp_interfaces.onprem
        asn     = var.bgp_asn.onprem
      }
      bgp_peer_options = {
        advertise_groups = ["ALL_SUBNETS"]
        advertise_ip_ranges = {
          (local.netblocks.dns)        = "DNS resolvers"
          (local.netblocks.private)    = "private.gooogleapis.com"
          (local.netblocks.restricted) = "restricted.gooogleapis.com"
          (var.ip_ranges.prod)         = "prod"
          (var.ip_ranges.nonprod)      = "nonprod"
        }
        advertise_mode = "CUSTOM"
        route_priority = 1000
      }
      bgp_session_range = "${local.bgp_interfaces.landing-onprem}/30"
      ike_version       = 2
      peer_ip           = module.vm-onprem.external_ips.0
      shared_secret     = ""
    }
  }
}

module "landing-vpn-to-prod" {
  source     = "../../modules/net-vpn-dynamic"
  project_id = module.landing-host.project_id
  region     = var.region
  network    = module.landing-vpc.name
  name       = "landing-to-prod"
  router_asn = var.bgp_asn.landing
  tunnels = {
    spoke-prod = {
      bgp_peer = {
        address = local.bgp_interfaces.prod
        asn     = var.bgp_asn.prod
      }
      bgp_peer_options = {
        advertise_groups = ["ALL_SUBNETS"]
        advertise_ip_ranges = {
          (var.ip_ranges.onprem) = "onprem"
        }
        advertise_mode = "CUSTOM"
        route_priority = 1000
      }
      bgp_session_range = "${local.bgp_interfaces.landing-prod}/30"
      ike_version       = 2
      peer_ip           = module.prod-vpn-to-landing.address
      shared_secret     = ""
    }
  }
}

module "landing-vpn-to-nonprod" {
  source     = "../../modules/net-vpn-dynamic"
  project_id = module.landing-host.project_id
  region     = var.region
  network    = module.landing-vpc.name
  name       = "landing-to-nonprod"
  router_asn = var.bgp_asn.landing
  tunnels = {
    spoke-noprod = {
      bgp_peer = {
        address = local.bgp_interfaces.nonprod
        asn     = var.bgp_asn.nonprod
      }
      bgp_peer_options = {
        advertise_groups = ["ALL_SUBNETS"]
        advertise_ip_ranges = {
          (var.ip_ranges.onprem) = "onprem"
        }
        advertise_mode = "CUSTOM"
        route_priority = 1000
      }
      bgp_session_range = "${local.bgp_interfaces.landing-nonprod}/30"
      ike_version       = 2
      peer_ip           = module.nonprod-vpn-to-landing.address
      shared_secret     = ""
    }
  }
}

###############################################################################
#                                   Services                                  #
###############################################################################

module "service-account-gce" {
  source     = "../../modules/iam-service-accounts"
  project_id = module.landing-host.project_id
  names      = ["gce-test"]
  iam_project_roles = {
    (module.landing-host.project_id) = [
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
    ]
  }
}

module "landing-host-vm" {
  source     = "../../modules/compute-vm"
  project_id = module.landing-host.project_id
  region     = var.region
  zone       = "${var.region}-b"
  name       = "test"
  network_interfaces = [{
    network    = module.landing-vpc.self_link,
    subnetwork = module.landing-vpc.subnet_self_links["${var.region}/landing"],
    nat        = false,
    addresses  = null
  }]
  metadata               = { startup-script = local.vm-startup-script }
  service_account        = module.service-account-gce.email
  service_account_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  tags                   = ["ssh"]
}

###############################################################################
#                                   GCS                                       #
###############################################################################
module "landing-buckets" {
  source     = "../../modules/gcs"
  project_id = module.landing-host.project_id
  prefix     = "lcaggio-g-03"
  names      = ["landing"]
  bucket_policy_only = {
    bucket-one = false
  }
  iam_members = {
    landing = {
      "roles/storage.admin" = [
        join(":", ["serviceAccount", module.service-account-gce.email]),
      join(":", ["serviceAccount", module.service-account-onprem.email]), ]
    }
  }
  iam_roles = {
    landing = ["roles/storage.admin"]
  }
}
