$User = [Security.Principal.WindowsIdentity]::GetCurrent()
$Role = ( New-Object Security.Principal.WindowsPrincipal $user ).IsInRole( [Security.Principal.WindowsBuiltinRole]::Administrator )
if ( -not $Role )
{
    Write-Warning "To perform some operations you must run an elevated Windows PowerShell console."
}
else
{
   
########################Gerekli dizinleri olusturur########################

New-Item -Path "D:\" -Name "LOGS" -ItemType "directory"
New-Item -Path "D:\LOGS" -Name "APPLOGS" -ItemType "directory"
New-Item -Path "D:\LOGS" -Name "IISLOGS" -ItemType "directory"
New-Item -Path "D:\LOGS" -Name "SYSLOGS" -ItemType "directory"

########################IIS default log path'leri degistirir########################

Import-Module WebAdministration
Set-WebConfigurationProperty "/system.applicationHost/sites/siteDefaults" -name logfile.directory -value "D:\LOGS\IISLOGS"
Set-WebConfigurationProperty "/system.applicationHost/sites/siteDefaults" -name traceFailedRequestsLogging.directory -value "D:\LOGS\FailedReqLogFiles"
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST'  -filter "system.applicationHost/sites/siteDefaults/logFile" -name "logSiteId" -value "False"
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST'  -filter "/system.applicationHost/sites/siteDefaults" -name "logfile.logExtFileFlags" -value "Date,Time,SiteName,ServerIP,Method,UriStem,UriQuery,ServerPort,UserName,ClientIP,UserAgent,HttpStatus,HttpSubStatus,Win32Status,BytesSent,BytesRecv,TimeTaken"
Add-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST'  -filter "system.applicationHost/sites/siteDefaults/logFile/customFields" -name "." -value @{logFieldName='x-forwarded-for';sourceName='X-Forwarded-For';sourceType='RequestHeader'}
Set-WebConfigurationProperty "/system.applicationHost/log" -name centralW3CLogFile.directory -value "D:\LOGS\IISLOGS"
Set-WebConfigurationProperty "/system.applicationHost/log" -name centralBinaryLogFile.directory -value "D:\LOGS\IISLOGS"

########################HTTPErr log path'i degistirir, sonrasinde net stop http ve start gerekli########################

$myRegKeyBase = "HKLM:\SYSTEM\CurrentControlSet\services\HTTP\Parameters"
$myRegKeyName = "ErrorLoggingDir"
$myRegKeyVal  = "D:\LOGS\SYSLOGS"
$myRC = New-ItemProperty $myRegKeyBase -Name $myRegKeyName -Value $myRegKeyVal -PropertyType String -ErrorAction SilentlyContinue

}

########################Servis halihazırda varsa, durdurur ve siler########################
if (Get-Service filebeat -ErrorAction SilentlyContinue) {
  $service = Get-WmiObject -Class Win32_Service -Filter "name='filebeat-new'"
  $service.StopService()
  Start-Sleep -s 1
  $service.delete()
}

$workdir = Split-Path $MyInvocation.MyCommand.Path

########################Yeni servis oluşturulur########################
New-Service -name filebeat-new `
  -displayName Filebeat-New `
  -binaryPathName "`"$workdir\filebeat.exe`" --environment=windows_service -c `"$workdir\filebeat.yml`" --path.home `"$workdir`" --path.data `"$env:PROGRAMDATA\filebeat-new`" --path.logs `"$env:PROGRAMDATA\filebeat-new\logs`" -E logging.files.redirect_stderr=true"

########################SC Config kullanarak servisi erteleyerek başlatır########################
Try {
  Start-Process -FilePath sc.exe -ArgumentList 'config filebeat start= delayed-auto'
}
Catch { Write-Host -f red "An error occured setting the service to delayed start." }

.\filebeat.exe setup
.\filebeat.exe setup --pipelines -modules=iis

Start-Service -Name "filebeat-new"
