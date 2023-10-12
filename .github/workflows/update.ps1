param (
    [string]$version = $(Get-Date -Format "yyyy.M.d.1")
)

function Extract-Updates {
    param (
        [Microsoft.UpdateServices.Administration.UpdateCollection]$updates = $(throw "-Updates is required"),
        [string]$build = $(throw "-Build is required"),
        [string]$version = $(throw "-Version is required")
    )

    $filtered = $updates | where-object { 
        (-not $_.IsSuperseded) -and 
        $_.Title -match "x64" -and 
        $_.Title -match $build -and 
        $_.PublicationState -eq "Published"
    }

    $updateOutput = @()
    foreach ($u in $filtered) {
        $UpdateGroup = switch -Wildcard ($u.LegacyName) {
            "*DotNetCumulative*" {"DotNetCU"}
            "*DotNetStandalone*" {"DotNet"}
            "*UnifiedCumulativeSecurity*" {"LCU"}
            "*ServicingStackUpdate*" {"SSU"}
            default {"Optional"}
        }

        foreach ($file in $u.GetInstallableItems().Files | 
            where-object {$_.Type -match "SelfContained"}) {
            $FileKBNumber = [RegEx]::Match($file.Name, "-KB(\d{7,})-").Groups[1].Value
            If ($FileKBNumber -eq "") {
                $FileKBNumber = $u.KnowledgebaseArticles[0]
            }

            $update = [ordered]@{
                    OSDVersion = $version
                    Id = $u.Id.UpdateId.Guid
                    Title = $u.Title
                    LegacyName = $u.LegacyName
                    KBNumber = $u.KnowledgebaseArticles[0]
                    CreationDate = $(Get-Date $u.CreationDate -UFormat '%Y-%m-%dT%H:%M:%SZ')
                    UpdateArch = "x64"
                    UpdateGroup = $UpdateGroup
                    FileKBNumber = $FileKBNumber
                    FileUri = $file.OriginUri
                    AdditionalHash = $file.AdditionalHash -join ' '
                }

            $updateOutput += $update
        }
    }

    return $updateOutput
}

Write-Host "> Installing Windows Feature `"UpdateServices`" - WSUS Role"
Install-WindowsFeature -Name UpdateServices -IncludeManagementTools

Write-Host "> Setting FullControl ACL for `"NT AUTHORITY\NetworkService`" on `"C:\Windows\temp`""
$NewAcl = Get-Acl -Path "C:\Windows\Temp"
# Set properties
$identity = "NT AUTHORITY\NetworkService"
$fileSystemRights = "FullControl"
$type = "Allow"
# Create new rule
$fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
$fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
# Apply new rule
$NewAcl.SetAccessRule($fileSystemAccessRule)
Set-Acl -Path "C:\Windows\Temp" -AclObject $NewAcl

Write-Host "> Running WSUS Post-install"
$WSUSDir = "C:\WSUS_Updates"
C:\Program` Files\Update` Services\Tools\wsusutil.exe postinstall CONTENT_DIR=$WSUSDir

$PostInstallLog = Get-Item "$env:UserProfile\AppData\Local\Temp\WSUS_PostInstall*.log"
if (Test-Path $PostInstallLog) {
    Move-Item -Path $PostInstallLog -Destination "C:\WSUS_PostInstall.log"
}

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

Write-Host "> Downloading SUSDB to load a bootstrap"
#Invoke-WebRequest -Uri $env:SUSDB -OutFile "C:\temp\SUSDB.bak"
Move-Item -Path "C:\SUSDB.bak" -Destination "C:\temp\SUSDB.bak"

Write-Host "> Stopping WSUS Service"
Stop-Service -Name "WsusService", "W3SVC"

Write-Host "> Restoring/Loading SUSDB"
$sqlcmd_path = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCmd.exe"
Start-Process -FilePath $sqlcmd_path -ArgumentList '-E -S np:\\.\pipe\MICROSOFT##WID\tsql\query -Q "RESTORE DATABASE [SUSDB] FROM DISK = N''C:\temp\SUSDB.bak'' WITH REPLACE"' -Wait -NoNewWindow

Write-Host "> Starting WSUS Service"
Start-Service -Name "WsusService", "W3SVC"

$wsus = Get-WSUSServer
$subscription = $wsus.GetSubscription()
Write-Host "> Starting WSUS Update/Sync"
$subscription.StartSynchronization()
While($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {
   $Total = $subscription.GetSynchronizationProgress() | Select-Object -ExpandProperty TotalItems
   $Processed = $subscription.GetSynchronizationProgress() | Select-Object -ExpandProperty ProcessedItems
   $Phases = $subscription.GetSynchronizationProgress() | Select-Object -ExpandProperty Phase
   Write-Host "Synchronised $Processed of $Total $Phases"
   Start-Sleep -Seconds 15
}

Write-Host "> Writing WSUS Extracts"
$updates = $wsus.GetUpdates()
$utf8 = New-Object System.Text.UTF8Encoding $false

$21h2 = (Extract-Updates -Updates $updates -Build "21H2" -Version $version | ConvertTo-Json) -replace "`r`n","`n"
Set-Content -Value $utf8.GetBytes($21h2) -Encoding Byte -Path windows-10-21h2.json
$22h2 = (Extract-Updates -Updates $updates -Build "22H2" -Version $version | ConvertTo-Json) -replace "`r`n","`n"
Set-Content -Value $utf8.GetBytes($22h2) -Encoding Byte -Path windows-10-22h2.json

Write-Host "> Stopping WSUS Service"
Stop-Service -Name "WsusService", "W3SVC"

Write-Host "> Creating backup of SUSDB"
$sqlcmd_path = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCmd.exe"
Start-Process -FilePath $sqlcmd_path -ArgumentList '-E -S np:\\.\pipe\MICROSOFT##WID\tsql\query -Q "BACKUP DATABASE [SUSDB] TO  DISK = N''C:\SUSDB.bak'' WITH  NOFORMAT, NOINIT,  NAME = N''SUSDB Full Backup'', NOSKIP, REWIND, NOUNLOAD, COMPRESSION,  STATS = 10, CHECKSUM"'  -Wait -NoNewWindow