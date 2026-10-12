# Pester tests for the NinjaOne API check that runs once before a per-tenant sync fan-out.

BeforeAll {
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/NinjaOne/Invoke-NinjaOneExtensionScheduler.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/NinjaOne/Invoke-NinjaOneSync.ps1"

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-AzDataTableEntity { param($TableName, $Filter) }
    function Add-AzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-NinjaOneToken { param($Configuration) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $message, $Sev, $tenant, $Headers) }
    function Get-Tenants { param([switch]$IncludeErrors) }
}

Describe 'NinjaOne sync fan-out API check' {
    BeforeEach {
        $script:Settings = @()
        Mock Add-AzDataTableEntity { }
        Mock Write-LogMessage { }
        Mock Start-CIPPOrchestrator { 'instance-1' }
        Mock Get-Tenants { [pscustomobject]@{ customerId = 't1'; defaultDomainName = 'a.onmicrosoft.com' } }
        Mock Get-AzDataTableEntity {
            switch ($TableName) {
                'NinjaOneSettings' { $script:Settings }
                'CippMapping' {
                    [pscustomobject]@{ RowKey = 't1'; IntegrationId = '10'; lastStartTime = (Get-Date).AddHours(-4).ToString('o'); lastEndTime = $null }
                    [pscustomobject]@{ RowKey = 't2'; IntegrationId = '11'; lastStartTime = (Get-Date).AddHours(-4).ToString('o'); lastEndTime = $null }
                }
                'Extensionsconfig' { [pscustomobject]@{ config = '{"NinjaOne":{"Enabled":true,"Instance":"eu.ninjarmm.com"}}' } }
            }
        }
    }

    It 'queues the daily sync when the API check passes' {
        Mock Get-NinjaOneToken { [pscustomobject]@{ access_token = 'tok' } }

        Invoke-NinjaOneExtensionScheduler

        Should -Invoke Get-NinjaOneToken -Times 1 -Exactly
        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly -ParameterFilter { $InputObject.Batch.Count -eq 2 }
    }

    It 'queues nothing and logs once when the API check fails, but still records the run' {
        Mock Get-NinjaOneToken { $null }

        Invoke-NinjaOneExtensionScheduler

        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' -and $message -like 'NinjaOne API check failed, daily synchronization not queued for 2 tenants*' }
        Should -Invoke Add-AzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RowKey -eq 'NinjaLastRunTime' }
    }

    It 'does not queue a catchup batch when the API check fails' {
        $Interval = ((Get-Date).Hour * 4) + [math]::Floor((Get-Date).Minute / 15)
        $script:Settings = @(
            [pscustomobject]@{ RowKey = 'NinjaSyncTime'; SettingValue = ($Interval + 10) % 96 }
            [pscustomobject]@{ RowKey = 'NinjaLastRunTime'; SettingValue = (Get-Date).AddHours(-2).ToString('o') }
        )
        Mock Get-NinjaOneToken { $null }

        Invoke-NinjaOneExtensionScheduler

        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like 'NinjaOne API check failed, catchup synchronization not queued for 2 tenants*' }
    }

    It 'skips the API check when there is nothing to queue' {
        Mock Get-AzDataTableEntity { if ($TableName -eq 'NinjaOneSettings') { $script:Settings } }
        Mock Get-NinjaOneToken { $null }

        Invoke-NinjaOneExtensionScheduler

        Should -Invoke Get-NinjaOneToken -Times 0 -Exactly
    }

    It 'stops the on-demand sync of all tenants when the API check fails' {
        Mock Get-NinjaOneToken { $null }

        Invoke-NinjaOneSync

        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like 'Could not start NinjaOne Sync NinjaOne API check failed*2 tenants*' }
    }

    It 'queues the on-demand sync of all tenants when the API check passes' {
        Mock Get-NinjaOneToken { [pscustomobject]@{ access_token = 'tok' } }

        Invoke-NinjaOneSync

        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly -ParameterFilter { $InputObject.Batch.Count -eq 2 }
    }

    It 'names each queued tenant sync after its tenant, so the queue does not list them as unknown' {
        Mock Get-NinjaOneToken { [pscustomobject]@{ access_token = 'tok' } }

        Invoke-NinjaOneExtensionScheduler
        Invoke-NinjaOneSync

        Should -Invoke Start-CIPPOrchestrator -Times 2 -Exactly -ParameterFilter {
            (@($InputObject.Batch.TenantFilter | Sort-Object) -join ',') -eq 'a.onmicrosoft.com,t2'
        }
    }
}
