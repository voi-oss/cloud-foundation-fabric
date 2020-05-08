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

module "prod-service-2" {
  source          = "../../modules/project"
  name            = "prod-2"
  parent          = var.root_node
  prefix          = var.prefix
  billing_account = var.billing_account_id
  services        = var.project_services
  oslogin         = true
}


###############################################################################
#                                   GCS                                       #
###############################################################################
module "prod-service-2-buckets" {
  source     = "../../modules/gcs"
  project_id = module.prod-service-2.project_id
  prefix     = "lcaggio-g-03"
  names      = ["prod-2"]
  bucket_policy_only = {
    bucket-one = false
  }
  iam_members = {
    prod-2 = {
      "roles/storage.admin" = [
        join(":", ["serviceAccount", module.service-account-gce.email]),
      join(":", ["serviceAccount", module.service-account-onprem.email]), ]
    }
  }
  iam_roles = {
    prod-2 = ["roles/storage.admin"]
  }
}
