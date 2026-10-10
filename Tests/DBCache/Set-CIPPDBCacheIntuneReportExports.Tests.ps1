# Pester tests for the Intune report-export cache collectors (DetectedApps, IntuneAppInstallStatus).
# Both read a completed export job's rows through Get-CIPPIntuneReportExportRows. DetectedApps folds
# the device x app rows into one row per app, sharing one device object per distinct device tuple;
# the stored JSON must match a fresh object per row. IntuneAppInstallStatus maps each rollup row.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheDetectedApps.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheIntuneAppInstallStatus.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneReportExportJob.ps1')

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

    Context 'export job not ready' {
        BeforeEach { Mock Start-Sleep {}; Mock Get-CIPPIntuneReportExportRows {}; Mock New-CIPPIntuneReportExportJob {} }

        It 'leaves a job that is still running for the next run' {
            Mock New-GraphGetRequest { [pscustomobject]@{ status = 'inProgress' } }
            Set-CIPPDBCacheDetectedApps -TenantFilter 'contoso.com'
            Set-CIPPDBCacheIntuneAppInstallStatus -TenantFilter 'contoso.com'
            Should -Invoke Get-CIPPIntuneReportExportRows -Times 0 -Exactly
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
            Should -Invoke Start-Sleep -Times 0 -Exactly
            $script:Written.Count | Should -Be 0
        }

        It 'submits a job when none is recorded, and returns without reading it' {
            Mock Get-CIPPAzDataTableEntity {}
            Set-CIPPDBCacheDetectedApps -TenantFilter 'contoso.com'
            Should -Invoke New-CIPPIntuneReportExportJob -Times 1 -Exactly -ParameterFilter { $ReportName -eq 'AppInvRawData' }
            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
            Should -Invoke Start-Sleep -Times 0 -Exactly
        }

        It 'drops a failed job so the next run submits a fresh one' {
            Mock New-GraphGetRequest { [pscustomobject]@{ status = 'failed' } }
            Set-CIPPDBCacheIntuneAppInstallStatus -TenantFilter 'contoso.com'
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
            Should -Invoke Get-CIPPIntuneReportExportRows -Times 0 -Exactly
        }

        It 'drops the job when its download fails, so an expired url is not retried' {
            Mock Get-CIPPIntuneReportExportRows { throw 'Response status code does not indicate success: 403' }
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

Describe 'Intune collection group' {
    BeforeAll {
        . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPDBCacheCollection.ps1')
    }

    It 'touches both exports before any collector runs, and reads them last' {
        $global:IntuneGroupCalls = [System.Collections.Generic.List[string]]::new()
        Mock Get-CIPPIntuneReportExportJob { $global:IntuneGroupCalls.Add("export:$ReportName") }
        Mock Get-Command { [pscustomobject]@{ Name = $Name } }
        Mock Write-LogMessage {}
        $Stub = { param($TenantFilter, $QueueId) $global:IntuneGroupCalls.Add($MyInvocation.MyCommand.Name -replace '^Set-CIPPDBCache') }
        foreach ($Type in 'ManagedDevices', 'IntunePolicies', 'IntuneApplications', 'IntuneAssignmentFilters', 'IntuneCompliancePolicies',
            'ManagedDeviceEncryptionStates', 'IntuneAppProtectionPolicies', 'IntuneScripts', 'IntuneReusableSettings', 'MDEOnboarding',
            'AutopilotDeploymentProfiles', 'DeviceEnrollmentConfigurations', 'IntuneDeviceManagementSettings', 'IntuneDataProcessorOnboarding',
            'IntuneBrandingProfile', 'ManagedDeviceCleanupRules') {
            Set-Item -Path "function:global:Set-CIPPDBCache$Type" -Value $Stub
        }

        $Result = Invoke-CIPPDBCacheCollection -CollectionType 'Intune' -TenantFilter 'contoso.com'

        $Result.Failed | Should -Be 0
        $Calls = @($global:IntuneGroupCalls)
        $Calls.Count | Should -Be 20
        $Calls[0..2] | Should -Be @('export:AppInvRawData', 'export:AppInstallStatusAggregate', 'ManagedDevices')
        $Calls[-3..-1] | Should -Be @('ManagedDeviceCleanupRules', 'export:AppInvRawData', 'export:AppInstallStatusAggregate')
    }
}
