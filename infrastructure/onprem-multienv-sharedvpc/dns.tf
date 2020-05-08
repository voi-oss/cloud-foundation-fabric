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

module "dns-gcp" {
  source          = "../../modules/dns"
  project_id      = module.landing-host.project_id
  type            = "private"
  name            = "gcp-example"
  domain          = "gcp.example.org."
  client_networks = [module.landing-vpc.self_link]
  recordsets = concat(
    [{ name = "localhost", type = "A", ttl = 300, records = ["127.0.0.1"] }],
    [
      for name, ip in zipmap(module.landing-host-vm.names, module.landing-host-vm.internal_ips) :
      { name = name, type = "A", ttl = 300, records = [ip] }
    ]
  )
}

module "dns-api" {
  source          = "../../modules/dns"
  project_id      = module.landing-host.project_id
  type            = "private"
  name            = "googleapis"
  domain          = "googleapis.com."
  client_networks = [module.landing-vpc.self_link]
  recordsets = [
    { name = "*", type = "CNAME", ttl = 300, records = ["private.googleapis.com."] },
    { name = "private", type = "A", ttl = 300, records = local.vips.private },
    { name = "restricted", type = "A", ttl = 300, records = local.vips.restricted },
  ]
}

module "dns-onprem" {
  source          = "../../modules/dns"
  project_id      = module.landing-host.project_id
  type            = "forwarding"
  name            = "onprem-example"
  domain          = "onprem.example.org."
  client_networks = [module.landing-vpc.self_link]
  forwarders      = [cidrhost(var.ip_ranges.onprem, 3)]
}

resource "google_dns_policy" "inbound" {
  provider                  = google-beta
  project                   = module.landing-host.project_id
  name                      = "gcp-inbound"
  enable_inbound_forwarding = true
  networks {
    network_url = module.landing-vpc.self_link
  }
}
