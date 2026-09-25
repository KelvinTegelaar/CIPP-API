# Pester tests for the Intune report-export cache collectors (DetectedApps, IntuneAppInstallStatus).
# Both read a completed export job's rows through Get-CIPPIntuneReportExportRows. DetectedApps folds
# the device x app rows into one row per app, sharing one device object per distinct device tuple;
# the stored JSON must match a fresh object per row. IntuneAppInstallStatus maps each rollup row.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheDetectedApps.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheIntuneAppInstallStatus.ps1')

    function Get-CIPPTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function New-CIPPIntuneReportExportJob { param($TenantFilter, $ReportName) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPIntuneReportExportRows { param($Url) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    # Static stub rather than a Mock: it must bind pipeline input the way the real one does.
    function Add-CIPPDbItem {
        [CmdletBinding()]
        param($TenantFilter, $Type, [Parameter(ValueFromPipeline)]$InputObject, $Data, [switch]$AddCount)
        process { foreach ($Item in @($InputObject) + @($Data)) { if ($null -ne $Item) { $script:Written.Add([pscustomobject]@{ Type = $Type; Item = $Item }) } } }
    }

    function New-AppRow ($Key, $Device, $User = 'u1') {
        $Row = [System.Collections.Generic.Dictionary[string, object]]::new()
        $Row['ApplicationKey'] = $Key; $Row['ApplicationName'] = "Name $Key"; $Row['ApplicationPublisher'] = 'Contoso'
        $Row['ApplicationVersion'] = '1.0'; $Row['DeviceId'] = "id-$Device"; $Row['DeviceName'] = $Device
        $Row['OSDescription'] = 'Windows'; $Row['OSVersion'] = '10.0'; $Row['Platform'] = 'Windows'
        $Row['UserId'] = $User; $Row['UserName'] = "User $User"; $Row['EmailAddress'] = "$User@contoso.com"
        $Row
    }
}

Describe 'Intune report-export collectors' {
    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'x'; JobId = 'job-1' } }
        Mock New-GraphGetRequest { [pscustomobject]@{ status = 'completed'; url = 'https://blob/export.zip' } }
        Mock Remove-CIPPAzDataTableEntity {}
        Mock Write-LogMessage {}
    }

    Context 'Set-CIPPDBCacheDetectedApps' {
        BeforeEach {
            Mock Get-CIPPIntuneReportExportRows {
                New-AppRow 'app-a' 'PC1'
                New-AppRow 'app-b' 'PC1'
                New-AppRow 'app-a' 'PC2'
                New-AppRow 'app-a' 'PC1' 'u2'   # same device, different user: a distinct tuple
                New-AppRow $null 'PC3'          # no application key: skipped
            }
        }

        It 'reads the completed job url through the streaming helper' {
            Set-CIPPDBCacheDetectedApps -TenantFilter 'contoso.com'
            Should -Invoke Get-CIPPIntuneReportExportRows -Times 1 -Exactly -ParameterFilter { $Url -eq 'https://blob/export.zip' }
        }

        It 'writes one row per app with every device row, in the stored shape' {
            Set-CIPPDBCacheDetectedApps -TenantFilter 'contoso.com'
            $Apps = @($script:Written | Where-Object Type -EQ 'DetectedApps' | ForEach-Object Item | Sort-Object id)
            $Apps.id | Should -Be @('app-a', 'app-b')
            $Apps[0].deviceCount | Should -Be 3
            $Apps[0].managedDevices.deviceName | Should -Be @('PC1', 'PC2', 'PC1')
            $Apps[0].managedDevices[2].userId | Should -Be 'u2'
            ($Apps[1] | ConvertTo-Json -Depth 100 -Compress) | Should -Be '{"id":"app-b","displayName":"Name app-b","version":"1.0","publisher":"Contoso","platform":"Windows","deviceCount":1,"managedDevices":[{"id":"id-PC1","deviceName":"PC1","osVersion":"10.0","platform":"Windows","userId":"u1","userPrincipalName":"User u1","emailAddress":"u1@contoso.com"}]}'
        }

        It 'shares one device object per distinct device tuple across apps' {
            Set-CIPPDBCacheDetectedApps -TenantFilter 'contoso.com'
            $Apps = @($script:Written | ForEach-Object Item | Sort-Object id)
            [object]::ReferenceEquals($Apps[0].managedDevices[0], $Apps[1].managedDevices[0]) | Should -BeTrue
            [object]::ReferenceEquals($Apps[0].managedDevices[0], $Apps[0].managedDevices[2]) | Should -BeFalse
        }

        It 'consumes the job row after caching' {
            Set-CIPPDBCacheDetectedApps -TenantFilter 'contoso.com'
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
        }
    }

    Context 'Set-CIPPDBCacheIntuneAppInstallStatus' {
        BeforeEach {
            Mock Get-CIPPIntuneReportExportRows {
                $Row = [System.Collections.Generic.Dictionary[string, object]]::new()
                $Row['ApplicationId'] = 'app-1'; $Row['DisplayName'] = 'App 1'; $Row['Publisher'] = 'Contoso'
                $Row['Platform'] = 'Windows'; $Row['AppVersion'] = '2.0'; $Row['InstalledDeviceCount'] = [long]5
                $Row['FailedDeviceCount'] = [long]2; $Row['FailedUserCount'] = [long]1; $Row['PendingInstallDeviceCount'] = [long]0
                $Row['NotInstalledDeviceCount'] = [long]3; $Row['FailedDevicePercentage'] = 20.5
                $Row
                $Skip = [System.Collections.Generic.Dictionary[string, object]]::new(); $Skip['DisplayName'] = 'no id'; $Skip
            }
        }

        It 'maps each rollup row with an application id' {
            Set-CIPPDBCacheIntuneAppInstallStatus -TenantFilter 'contoso.com'
            $Rows = @($script:Written | Where-Object Type -EQ 'IntuneAppInstallStatusAggregate' | ForEach-Object Item)
            $Rows.Count | Should -Be 1
            $Rows[0].id | Should -Be 'app-1'
            $Rows[0].platform | Should -Be 'Windows'
            $Rows[0].failedDeviceCount | Should -Be 2
            $Rows[0].failedDeviceCount | Should -BeOfType [int]
            $Rows[0].failedDevicePercentage | Should -Be 20.5
        }
    }
}
