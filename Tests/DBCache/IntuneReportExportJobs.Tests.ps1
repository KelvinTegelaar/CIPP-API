# Pester tests for the Intune report-export job lifecycle: submit (New-), poll (Get-) and the sweep that
# reads exports the nightly cache run left behind. Intune intermittently answers 500 for some tenants and
# deletes the download 6 hours after the export completes.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneReportExportJob.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPIntuneReportExportJob.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Orchestrator Functions/Start-IntuneReportExportSweep.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheSensitivityLabels.ps1')

    function Get-CIPPTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    $script:Ago = { param($Hours) [datetime]::UtcNow.AddHours(-$Hours).ToString('o') }
}

Describe 'Get-CIPPIntuneReportExportJob' {
    BeforeEach {
        Mock Start-Sleep {}
        Mock Write-LogMessage {}
        Mock Remove-CIPPAzDataTableEntity {}
        Mock New-CIPPIntuneReportExportJob {}
        Mock New-GraphGetRequest { [pscustomobject]@{ status = 'completed'; url = 'https://blob/export.zip' } }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'AppInvRawData'; JobId = 'job-1'; SubmittedAt = (& $script:Ago 1) } }
    }

    It 'resubmits a job older than the 6 hour download window without polling it' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'AppInvRawData'; JobId = 'job-1'; SubmittedAt = (& $script:Ago 7) } }
        Get-CIPPIntuneReportExportJob -TenantFilter 'contoso.com' -ReportName 'AppInvRawData' | Should -BeNullOrEmpty
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
        Should -Invoke New-CIPPIntuneReportExportJob -Times 1 -Exactly -ParameterFilter { $ReportName -eq 'AppInvRawData' }
    }

    It 'retries a poll that fails, and returns the export once Intune answers' {
        $script:Calls = 0
        Mock New-GraphGetRequest {
            $script:Calls++
            if ($script:Calls -lt 3) { throw 'An internal server error has occurred.' }
            [pscustomobject]@{ status = 'completed'; url = 'https://blob/export.zip' }
        }
        $Export = Get-CIPPIntuneReportExportJob -TenantFilter 'contoso.com' -ReportName 'AppInvRawData'
        $Export.Url | Should -Be 'https://blob/export.zip'
        Should -Invoke New-GraphGetRequest -Times 3 -Exactly
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'keeps the job for the next poll when every attempt fails' {
        Mock New-GraphGetRequest { throw 'An internal server error has occurred.' }
        Get-CIPPIntuneReportExportJob -TenantFilter 'contoso.com' -ReportName 'AppInvRawData' | Should -BeNullOrEmpty
        Should -Invoke New-GraphGetRequest -Times 3 -Exactly
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke New-CIPPIntuneReportExportJob -Times 0 -Exactly
    }
}

Describe 'New-CIPPIntuneReportExportJob' {
    BeforeEach {
        Mock Start-Sleep {}
        Mock Get-CIPPAzDataTableEntity {}
        Mock Add-CIPPAzDataTableEntity {}
    }

    It 'retries a submit that fails and records the job' {
        $script:Calls = 0
        Mock New-GraphPOSTRequest {
            $script:Calls++
            if ($script:Calls -eq 1) { throw 'An internal server error has occurred.' }
            [pscustomobject]@{ id = 'AppInvRawData_abc' }
        }
        (New-CIPPIntuneReportExportJob -TenantFilter 'contoso.com' -ReportName 'AppInvRawData').id | Should -Be 'AppInvRawData_abc'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.JobId -eq 'AppInvRawData_abc' }
    }

    It 'throws after three failed submits without recording a job' {
        Mock New-GraphPOSTRequest { throw 'An internal server error has occurred.' }
        { New-CIPPIntuneReportExportJob -TenantFilter 'contoso.com' -ReportName 'AppInvRawData' } | Should -Throw '*internal server error*'
        Should -Invoke New-GraphPOSTRequest -Times 3 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}

Describe 'Start-IntuneReportExportSweep' {
    BeforeEach {
        $script:Started = [System.Collections.Generic.List[object]]::new()
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject) }
    }

    It 'queues a read for each export the cache run left, skipping ones the run is still due to read' {
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ PartitionKey = 'a.com'; RowKey = 'AppInvRawData'; SubmittedAt = (& $script:Ago 3) }
            [pscustomobject]@{ PartitionKey = 'a.com'; RowKey = 'AppInstallStatusAggregate'; SubmittedAt = (& $script:Ago 5) }
            [pscustomobject]@{ PartitionKey = 'b.com'; RowKey = 'AppInvRawData'; SubmittedAt = (& $script:Ago 0.5) }
            [pscustomobject]@{ PartitionKey = 'b.com'; RowKey = 'NoncompliantDevicesAndSettingsV3'; SubmittedAt = (& $script:Ago 4) }
        }
        Start-IntuneReportExportSweep
        $script:Started.Count | Should -Be 1
        $Batch = @($script:Started[0].Batch)
        ($Batch | ForEach-Object { "$($_.TenantFilter)/$($_.Name)/$($_.FunctionName)" }) | Should -Be @('a.com/DetectedApps/ExecCIPPDBCache', 'a.com/IntuneAppInstallStatus/ExecCIPPDBCache', 'b.com/IntuneNonCompliantSettings/ExecCIPPDBCache')
    }

    It 'starts nothing when no export is waiting' {
        Mock Get-CIPPAzDataTableEntity {}
        Start-IntuneReportExportSweep
        $script:Started.Count | Should -Be 0
    }
}

Describe 'Set-CIPPDBCacheSensitivityLabels' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
        Mock Test-CIPPStandardLicense { $true }
    }

    It 'records an empty set when Graph has no labels for the tenant' {
        Mock New-GraphGetRequest { throw 'The resource could not be found.' }
        Set-CIPPDBCacheSensitivityLabels -TenantFilter 'contoso.com'
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ClearOnEmpty -and @($Data).Count -eq 0 }
    }

    It 'writes nothing when the read fails for another reason' {
        Mock New-GraphGetRequest { throw 'An internal server error has occurred.' }
        Set-CIPPDBCacheSensitivityLabels -TenantFilter 'contoso.com'
        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
    }
}
