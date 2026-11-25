# A tenant restore can name the items to restore per category. Only those reach Microsoft or the
# table; without a list the whole category restores, and an empty list restores nothing.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Public = Join-Path $RepoRoot 'Modules/CIPPCore/Public'

    function Get-CIPPBackup { param($Type, $Name) }
    function Get-CIPPTable { param($TableName) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type) }
    function New-CIPPCAPolicy { param($replacePattern, $Overwrite, $TenantFilter, $state, $RawJSON, $APIName) }
    function Set-CIPPIntunePolicy { param($TemplateType, $TenantFilter, $DisplayName, $Description, $RawJSON, $Headers, $APINAME) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdparams, [bool]$UseSystemMailbox) }
    function New-passwordString { 'P@ss' }
    function New-PwPushLink { param($Payload) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Get-NormalizedError { param($Message) $Message }

    . (Join-Path $Public 'New-CIPPRestoreTask.ps1')
    . (Join-Path $Public 'New-CIPPRestore.ps1')

    # Shaped as New-CIPPBackupTask stores it: CA entries are JSON strings, anti-spam is a JSON string.
    $script:Backup = [pscustomobject]@{
        users             = @(
            [pscustomobject]@{ id = 'u1'; userPrincipalName = 'a@contoso.com'; displayName = 'A' }
            [pscustomobject]@{ id = 'u2'; userPrincipalName = 'b@contoso.com'; displayName = 'B' }
            [pscustomobject]@{ id = 'u3'; userPrincipalName = 'c@contoso.com'; displayName = 'C' }
        )
        ca                = @(
            '{"displayName":"Block legacy auth","state":"enabled"}'
            '{"displayName":"Require MFA","state":"enabled"}'
            'Failed to create a template of the Conditional Access Policy with ID: x'
        )
        intuneconfig      = @(
            [pscustomobject]@{ Type = 'Catalog'; DisplayName = 'Baseline'; Description = ''; TemplateJson = '{}' }
            [pscustomobject]@{ Type = 'Device'; DisplayName = 'Baseline'; Description = ''; TemplateJson = '{}' }
        )
        antispam          = (@{
                policies = @(@{ Identity = 'Default'; Name = 'Default' }, @{ Identity = 'Strict'; Name = 'Strict' })
                rules    = @(@{ Identity = 'Strict rule'; Name = 'Strict rule'; HostedContentFilterPolicy = 'Strict'; State = 'Enabled' })
            } | ConvertTo-Json -Depth 5)
        CippWebhookAlerts = @(
            [pscustomobject]@{ PartitionKey = 'Webhookv2'; RowKey = 'w1' }
            [pscustomobject]@{ PartitionKey = 'Webhookv2'; RowKey = 'w2' }
        )
    }

    function Invoke-Restore {
        param([string]$Task, $Items, [switch]$NoItems)
        $Params = @{ Task = $Task; TenantFilter = 'contoso.onmicrosoft.com'; backup = 'contoso_2026-11-25-0100'; overwrite = $false; APINAME = 'Restore'; Headers = @{} }
        if (-not $NoItems) { $Params.Items = $Items }
        New-CIPPRestoreTask @Params
    }
}

Describe 'New-CIPPRestoreTask item selection' {
    BeforeEach {
        # A fresh copy each time: the filter replaces the category on the parsed backup.
        Mock Get-CIPPBackup { $script:Backup | ConvertTo-Json -Depth 10 | ConvertFrom-Json }
        Mock Get-CIPPTable { @{ TableName = 'WebhookRules' } }
        Mock Add-CIPPAzDataTableEntity { }
        Mock New-GraphGetRequest { @() }
        Mock New-GraphPOSTRequest { }
        Mock New-CIPPCAPolicy { }
        Mock Set-CIPPIntunePolicy { }
        Mock New-ExoRequest { @() }
        Mock Write-LogMessage { }
    }

    It 'restores every user when no items are named' {
        $null = Invoke-Restore -Task 'users' -NoItems
        Should -Invoke New-GraphPOSTRequest -Times 3 -Exactly
    }

    It 'restores only the named users' {
        $null = Invoke-Restore -Task 'users' -Items @('u1', 'U3')
        Should -Invoke New-GraphPOSTRequest -Times 2 -Exactly
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly -ParameterFilter { ($body | ConvertFrom-Json).userPrincipalName -eq 'b@contoso.com' }
    }

    It 'restores nothing for an empty list' {
        $Result = Invoke-Restore -Task 'users' -Items @()
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        $Result | Should -Contain 'No items were restored from backup.'
    }

    It 'matches Conditional Access templates on their display name and skips failed captures' {
        $null = Invoke-Restore -Task 'ca' -Items @('Require MFA')
        Should -Invoke New-CIPPCAPolicy -Times 1 -Exactly -ParameterFilter { ($RawJSON | ConvertFrom-Json).displayName -eq 'Require MFA' }
    }

    It 'tells same-named Intune policies apart by type' {
        $Result = Invoke-Restore -Task 'intuneconfig' -Items @('Device|Baseline')
        Should -Invoke Set-CIPPIntunePolicy -Times 1 -Exactly -ParameterFilter { $TemplateType -eq 'Device' }
        $Result | Should -Contain 'Restored: 1 IntuneConfig from backup'
    }

    It 'brings an anti-spam policy''s rule along with it' {
        $null = Invoke-Restore -Task 'antispam' -Items @('Strict')
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'New-HostedContentFilterPolicy' -and $cmdparams.Name -eq 'Strict' }
        Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $cmdlet -eq 'New-HostedContentFilterPolicy' -and $cmdparams.Name -eq 'Default' }
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'New-HostedContentFilterRule' -and $cmdparams.HostedContentFilterPolicy -eq 'Strict' }
    }

    It 'matches CIPP table rows on RowKey' {
        $null = Invoke-Restore -Task 'CippWebhookAlerts' -Items @('w2')
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { @($Entity).Count -eq 1 -and @($Entity)[0].RowKey -eq 'w2' }
    }
}

Describe 'New-CIPPRestore item selection' {
    BeforeEach {
        Mock New-CIPPRestoreTask { [pscustomobject]@{ Task = $Task; HasItems = $null -ne $Items; Items = $Items } }
        Mock Write-LogMessage { }
    }

    It 'passes each category its own list, as the scheduler hands it over' {
        # Push-ExecScheduledCommand round-trips the stored parameters through ConvertFrom-Json -AsHashtable.
        $RestoreValues = @{ backup = 'b'; overwrite = $false; users = $true; groups = $true; items = @{ users = @('u1') } } |
            ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
        $Result = New-CIPPRestore -TenantFilter 'contoso.onmicrosoft.com' -RestoreValues $RestoreValues

        $Users = $Result | Where-Object Task -EQ 'users'
        $Users.HasItems | Should -BeTrue
        $Users.Items | Should -Be @('u1')
        ($Result | Where-Object Task -EQ 'groups').HasItems | Should -BeFalse
        $Result.Task | Should -Not -Contain 'items'
    }
}
