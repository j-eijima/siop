variable "project" {
  description = "The GCP project the RP runs in."
  type        = string
}

variable "region" {
  description = "Where the RP and its image registry live."
  type        = string
  default     = "asia-northeast1"
}

variable "service" {
  description = "The Cloud Run service name, which becomes part of the RP's URL."
  type        = string
  default     = "siop-rp"
}

variable "image" {
  description = "The RP image to run. deploy.sh builds it and passes it in."
  type        = string
}
