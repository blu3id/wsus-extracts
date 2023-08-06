Write-Host "> Installing Windows Feature `"UpdateServices`" - WSUS Role"
Install-WindowsFeature -Name UpdateServices -IncludeManagementTools

Write-Host "> Running WSUS Post-install"
$WSUSDir = "C:\WSUS_Updates"
C:\Program` Files\Update` Services\Tools\wsusutil.exe postinstall CONTENT_DIR=$WSUSDir

$wsus = Get-WSUSServer
 
# Set Update Languages to English and save configuration settings
$wsusConfig = $wsus.GetConfiguration()
$wsusConfig.AllUpdateLanguagesEnabled = $false
$wsusConfig.AllUpdateLanguagesDssEnabled = $false
$wsusConfig.SetEnabledUpdateLanguages("en")
$wsusConfig.Save()

# Set to download updates from Microsoft Updates
Set-WsusServerSynchronization –SyncFromMU
Get-WsusProduct | Set-WsusProduct -Disable
Get-WsusClassification | Set-WsusClassification -Disable

# Initial sync to get categories
$subscription = $wsus.GetSubscription()
Write-Host "> Running WSUS Initial Category Sync"
$subscription.StartSynchronizationForCategoryOnly()
Write-Host "  Please wait"
While ($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 5
}
Write-Host ' '

# Configure the Platforms that we want WSUS to receive updates
Write-Host "> Configuring WSUS Categories (Products)"
Get-WsusProduct | Set-WsusProduct -Disable
Get-WsusProduct | where-Object {
    $_.Product.Title -in (
    'Windows 10, version 1903 and later')
} | Set-WsusProduct

# Configure the Classifications
Write-Host "> Configuring WSUS Classifications"
Get-WsusClassification | Set-WsusClassification -Disable
Get-WsusClassification | Where-Object {
    $_.Classification.Title -in (
    'Critical Updates',
    'Security Updates',
    'Updates')
} | Set-WsusClassification

Write-Host "> Starting WSUS Initial Sync. This will take some time."
$subscription.StartSynchronization()
While($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {
   $Total = $subscription.GetSynchronizationProgress() | Select-Object -ExpandProperty TotalItems
   $Processed = $subscription.GetSynchronizationProgress() | Select-Object -ExpandProperty ProcessedItems
   $Phases = $subscription.GetSynchronizationProgress() | Select-Object -ExpandProperty Phase
   Write-Host "Synchronised $Processed of $Total $Phases"
   Start-Sleep -Seconds 15
}

Write-Host "> WSUS Initial Sync Complete!"

Write-Host "> Downloading SQLCmd and dependencies"
New-Item -Path "C:\" -Name "temp" -ItemType "directory" -Force | Out-Null

$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri "https://aka.ms/vs/15/release/vc_redist.x64.exe" -OutFile "C:\temp\vc_redist.x64.exe"
Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2239168" -OutFile "C:\temp\msodbcsql.msi"
Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2230791" -OutFile "C:\temp\MsSqlCmdLnUtils.msi"

Write-Host "> Installing SQLCmd and dependencies"
Start-Process -FilePath "C:\temp\vc_redist.x64.exe" -ArgumentList "/install /quiet /norestart" -Wait -NoNewWindow
Start-Process -FilePath msiexec -ArgumentList "/i C:\temp\msodbcsql.msi /qn /passive IACCEPTMSODBCSQLLICENSETERMS=YES" -Wait -NoNewWindow
Start-Process -FilePath msiexec -ArgumentList "/i C:\temp\MsSqlCmdLnUtils.msi /qn /passive IACCEPTMSSQLCMDLNUTILSLICENSETERMS=YES" -Wait -NoNewWindow

Write-Host "> Stopping WSUS Service"
Stop-Service -Name "WsusService", "W3SVC"

Write-Host "> Creating backup of SUSDB"
$sqlcmd_path = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCmd.exe"
Start-Process -FilePath $sqlcmd_path -ArgumentList '-E -S np:\\.\pipe\MICROSOFT##WID\tsql\query -Q "BACKUP DATABASE [SUSDB] TO  DISK = N''C:\Temp\SUSDB.bak'' WITH  NOFORMAT, NOINIT,  NAME = N''SUSDB Full Backup'', NOSKIP, REWIND, NOUNLOAD, COMPRESSION,  STATS = 10, CHECKSUM"'