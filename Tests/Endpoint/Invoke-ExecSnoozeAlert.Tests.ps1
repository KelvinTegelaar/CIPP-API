# Pester tests for Invoke-ExecSnoozeAlert
#
# The endpoint is AnyTenant, so the framework's per-tenant check is skipped and the
# endpoint gates the caller-supplied TenantFilter itself: restricted callers may only
# snooze alerts for tenants the scope-narrowed Get-Tenants can resolve.
#
# A snooze is either timed (7, 14, 30 or 90 days) or "until resolved"; there is no
# indefinite snooze. KeepVisible leaves the item on the dashboard. The tracked
# AlertLifecycle row, when one exists and is not resolved, flips to Snoozed straight away.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecSnoozeAlert.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecSnoozeAlert.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-AlertContentHash { param($AlertItem) }
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $TableName, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $TableName, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList, [switch]$GroupList) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CippException { param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPAlertLifecycleKey.ps1')

    . $FunctionPath

    function New-SnoozeRequest {
        param($TenantFilter = 'contoso.onmicrosoft.com', $Duration = 7, $UntilResolved, $KeepVisible, $Reason = 'test')
        $Body = @{
            CmdletName   = 'Get-CIPPAlertSomething'
            TenantFilter = $TenantFilter
            AlertItem    = @{ Message = 'alert text' }
            Reason       = $Reason
        }
        if ($null -ne $Duration) { $Body.Duration = $Duration }
        if ($null -ne $UntilResolved) { $Body.UntilResolved = $UntilResolved }
        if ($null -ne $KeepVisible) { $Body.KeepVisible = $KeepVisible }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecSnoozeAlert' }
            Headers = @{ }
            Body    = [pscustomobject]$Body
        }
    }

    function Get-Written {
        param($Table)
        ($script:Written | Where-Object { $_.Table -eq $Table } | Select-Object -Last 1).Entity
    }
}

Describe 'Invoke-ExecSnoozeAlert' {
    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = $tablename } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName ConvertTo-CIPPODataFilterValue -MockWith { $Value }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Written.Add(@{ Table = $TableName; Entity = $Entity }) }
        Mock -CommandName Get-AlertContentHash -MockWith {
            @{ ContentHash = 'hash123'; ContentPreview = 'alert text'; RawKey = 'raw' }
        }
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.onmicrosoft.com' }
        }
    }

    It 'writes a timed snooze row for an unrestricted caller' {
        $Response = Invoke-ExecSnoozeAlert -Request (New-SnoozeRequest -Duration 14) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'AlertSnooze' }
        $Snooze = Get-Written -Table 'AlertSnooze'
        $Snooze.PartitionKey | Should -Be 'Get-CIPPAlertSomething'
        $Snooze.RowKey | Should -Be 'contoso.onmicrosoft.com-hash123'
        $Snooze.UntilResolved | Should -Be 'False'
        $Snooze.KeepVisible | Should -Be 'False'
        $Now = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        ([int64]$Snooze.SnoozeUntil) | Should -BeGreaterThan ($Now + 13 * 86400)
        ([int64]$Snooze.SnoozeUntil) | Should -BeLessOrEqual ($Now + 14 * 86400)
    }

    It 'writes an until-resolved snooze that keeps the item visible' {
        $Response = Invoke-ExecSnoozeAlert -Request (New-SnoozeRequest -Duration $null -UntilResolved $true -KeepVisible $true) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.UntilResolved | Should -BeTrue
        $Response.Body.KeepVisible | Should -BeTrue
        $Snooze = Get-Written -Table 'AlertSnooze'
        $Snooze.UntilResolved | Should -Be 'True'
        $Snooze.KeepVisible | Should -Be 'True'
        $Snooze.SnoozeUntil | Should -Be '0'
    }

    It 'rejects durations outside 7/14/30/90, including the old forever value' {
        foreach ($Bad in @(-1, 0, 3, 365)) {
            $Response = Invoke-ExecSnoozeAlert -Request (New-SnoozeRequest -Duration $Bad) -TriggerMetadata $null
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        }
        $Response = Invoke-ExecSnoozeAlert -Request (New-SnoozeRequest -Duration $null) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'marks the tracked alert item as snoozed when one exists' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{
                PartitionKey = 'contoso.onmicrosoft.com'
                RowKey       = 'Get-CIPPAlertSomething-hash123'
                Status       = 'Open'
                ContentHash  = 'hash123'
                ETag         = 'W/"1"'
            }
        }

        $Response = Invoke-ExecSnoozeAlert -Request (New-SnoozeRequest -Duration $null -UntilResolved $true -KeepVisible $true -Reason 'ticket 42') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'AlertLifecycle' -and $Filter -eq "PartitionKey eq 'contoso.onmicrosoft.com' and RowKey eq 'Get-CIPPAlertSomething-hash123'" }
        $Tracked = Get-Written -Table 'AlertLifecycle'
        $Tracked.Status | Should -Be 'Snoozed'
        $Tracked.SnoozeRowKey | Should -Be 'contoso.onmicrosoft.com-hash123'
        $Tracked.SnoozeReason | Should -Be 'ticket 42'
        $Tracked.SnoozeVisible | Should -Be 'True'
        $Tracked.SnoozeUntilResolved | Should -Be 'True'
        $Tracked.Keys | Should -Not -Contain 'ETag'
    }

    It 'leaves a resolved tracked item alone' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = 'contoso.onmicrosoft.com'; RowKey = 'Get-CIPPAlertSomething-hash123'; Status = 'Resolved' }
        }

        $null = Invoke-ExecSnoozeAlert -Request (New-SnoozeRequest) -TriggerMetadata $null

        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'AlertLifecycle' }
    }

    It 'refuses a restricted caller naming a tenant outside their scope' {
        Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }
        # Scope-narrowed Get-Tenants: the requested tenant resolves to nothing.
        Mock -CommandName Get-Tenants -MockWith { }

        $Response = Invoke-ExecSnoozeAlert -Request (New-SnoozeRequest -TenantFilter 'other.onmicrosoft.com') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'writes the snooze row for a restricted caller scoped to the tenant' {
        Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }

        $Response = Invoke-ExecSnoozeAlert -Request (New-SnoozeRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }
}
