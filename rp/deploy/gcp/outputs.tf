output "url" {
  description = "Open this on the device that has the SIOP app."
  value       = google_cloud_run_v2_service.rp.uri
}

output "redirect_uri" {
  description = "The client_id and redirect_uri the RP will send, derived from the URL it is opened at."
  value       = "${google_cloud_run_v2_service.rp.uri}/callback.html"
}
