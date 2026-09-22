# Pester tests for Invoke-ListAlertResults
#
# The endpoint reads the AlertLifecycle table. Open, Acknowledged and Snoozed rows always
# come back; Resolved rows only with IncludeResolved=true and only when resolved within
# the last Days days. Every row carries the keys the frontend needs to snooze, unsnooze
# or acknowledge it, and rows are narrowed to the caller's tenants.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListAlertResults.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListAlertResults.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $TableName, $Filter, $Property) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Get-CippException { param($Exception) }
    function Select-CippAllowedTenantData {
        param([Parameter(ValueFromPipeline)]$InputObject, $TenantProperty)
        process { $InputObject }
    }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPAlertLifecycleKey.ps1')
    . $FunctionPath

    function New-ListRequest {
        param($TenantFilter = 'contoso.onmicrosoft.com', $IncludeResolved, $Days)
        $Query = @{ tenantFilter = $TenantFilter }
        if ($null -ne $IncludeResolved) { $Query.IncludeResolved = $IncludeResolved }
        if ($null -ne $Days) { $Query.Days = $Days }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListAlertResults' }
            Headers = @{ }
            Body    = [pscustomobject]@{ }
            Query   = [pscustomobject]$Query
        }
    }

    function New-Row {
        param($Tenant = 'contoso.onmicrosoft.com', $Hash, $Status = 'Open', $ResolvedAt = '', $LastSeen = '2026-09-22T10:00:00.0000000Z')
        [pscustomobject]@{
            PartitionKey    = $Tenant
            RowKey          = "Get-CIPPAlertSomething-$Hash"
            CmdletName      = 'Get-CIPPAlertSomething'
            Tenant          = $Tenant
            ContentHash     = $Hash
            ContentPreview  = "item $Hash"
            AlertItem       = '{"Message":"item"}'
            AlertComment    = ''
            Status          = $Status
            FirstSeen       = '2026-09-20T10:00:00.0000000Z'
            LastSeen        = $LastSeen
            LastChecked     = $LastSeen
            ResolvedAt      = $ResolvedAt
            ReopenCount     = '2'
            AcknowledgedBy  = ''
            AcknowledgedAt  = ''
            AcknowledgeNote = ''
            SnoozeUntil     = ''
            SnoozedBy       = ''
            SnoozeRowKey    = ''
        }
    }
}

Describe 'Invoke-ListAlertResults' {
    BeforeEach {
        $script:Rows = @()
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = 'AlertLifecycle' } }
        Mock -CommandName ConvertTo-CIPPODataFilterValue -MockWith { $Value }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:Rows }
    }

    It 'requires a tenantFilter' {
        $Response = Invoke-ListAlertResults -Request (New-ListRequest -TenantFilter '') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'returns open, acknowledged and snoozed rows but hides resolved ones by default' {
        $script:Rows = @(
            (New-Row -Hash 'a' -Status 'Open'),
            (New-Row -Hash 'b' -Status 'Acknowledged'),
            (New-Row -Hash 'c' -Status 'Snoozed'),
            (New-Row -Hash 'd' -Status 'Resolved' -ResolvedAt ([datetime]::UtcNow.AddHours(-1).ToString('o')))
        )

        $Response = Invoke-ListAlertResults -Request (New-ListRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($Response.Body).Count | Should -Be 3
        @($Response.Body).Status | Should -Not -Contain 'Resolved'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -eq "PartitionKey eq 'contoso.onmicrosoft.com'" }
    }

    It 'includes resolved rows within the window when asked, and sorts them last' {
        $script:Rows = @(
            (New-Row -Hash 'old' -Status 'Resolved' -ResolvedAt ([datetime]::UtcNow.AddDays(-10).ToString('o'))),
            (New-Row -Hash 'fresh' -Status 'Resolved' -ResolvedAt ([datetime]::UtcNow.AddHours(-3).ToString('o'))),
            (New-Row -Hash 'open' -Status 'Open')
        )

        $Response = Invoke-ListAlertResults -Request (New-ListRequest -IncludeResolved 'true' -Days 2) -TriggerMetadata $null

        @($Response.Body).Count | Should -Be 2
        @($Response.Body)[0].ContentHash | Should -Be 'open'
        @($Response.Body)[1].ContentHash | Should -Be 'fresh'
    }

    It 'derives the snooze keys and parses the alert item' {
        $script:Rows = @(New-Row -Hash 'abc/def' -Status 'Open')

        $Response = Invoke-ListAlertResults -Request (New-ListRequest) -TriggerMetadata $null

        $Row = @($Response.Body)[0]
        $Row.SnoozePartitionKey | Should -Be 'Get-CIPPAlertSomething'
        $Row.SnoozeRowKey | Should -Be 'contoso.onmicrosoft.com-abc_def'
        $Row.AlertItem.Message | Should -Be 'item'
        $Row.ReopenCount | Should -Be 2
        $Row.RowKey | Should -Be 'Get-CIPPAlertSomething-abc/def'
    }

    It 'prefers the stored snooze row key when the reconciler recorded one' {
        $Row = New-Row -Hash 'abc' -Status 'Snoozed'
        $Row.SnoozeRowKey = 'stored-key'
        $script:Rows = @($Row)

        $Response = Invoke-ListAlertResults -Request (New-ListRequest) -TriggerMetadata $null

        @($Response.Body)[0].SnoozeRowKey | Should -Be 'stored-key'
    }

    It 'reads the whole table for AllTenants and narrows it to allowed tenants' {
        $script:Rows = @(
            (New-Row -Tenant 'contoso.onmicrosoft.com' -Hash 'a'),
            (New-Row -Tenant 'fabrikam.onmicrosoft.com' -Hash 'b')
        )
        Mock -CommandName Select-CippAllowedTenantData -MockWith {
            process { if ($InputObject.Tenant -eq 'contoso.onmicrosoft.com') { $InputObject } }
        }

        $Response = Invoke-ListAlertResults -Request (New-ListRequest -TenantFilter 'AllTenants') -TriggerMetadata $null

        @($Response.Body).Count | Should -Be 1
        @($Response.Body)[0].Tenant | Should -Be 'contoso.onmicrosoft.com'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { [string]::IsNullOrEmpty($Filter) }
    }

    It 'clamps Days to the allowed range' {
        $script:Rows = @(New-Row -Hash 'a' -Status 'Resolved' -ResolvedAt ([datetime]::UtcNow.AddDays(-400).ToString('o')))

        $Response = Invoke-ListAlertResults -Request (New-ListRequest -IncludeResolved 'true' -Days 9999) -TriggerMetadata $null

        @($Response.Body).Count | Should -Be 0
    }
}
