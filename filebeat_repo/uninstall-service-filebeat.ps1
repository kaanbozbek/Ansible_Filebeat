# Delete and stop the service if it already exists.
if (Get-Service filebeat-new -ErrorAction SilentlyContinue) {
  $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat-new'"
  $service.StopService()
  Start-Sleep -s 1
  $service.delete()
}
