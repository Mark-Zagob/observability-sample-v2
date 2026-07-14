#--------------------------------------------------------------
# Grafana Config — Outputs
#--------------------------------------------------------------

output "datasource_uids" {
  description = "Map of data source UIDs — dùng để reference trong dashboard JSON"
  value = {
    prometheus = grafana_data_source.prometheus.uid
    xray       = grafana_data_source.xray.uid
    cloudwatch = grafana_data_source.cloudwatch.uid
  }
}
