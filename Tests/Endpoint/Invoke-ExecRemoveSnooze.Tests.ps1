# Pester tests for Invoke-ExecRemoveSnooze
#
# The delete is keyed by raw PartitionKey/RowKey. The endpoint reads the row first for
# everyone: restricted callers only delete when the row's Tenant resolves through the
# scope-narrowed Get-Tenants, and the row's Tenant and ContentHash locate the tracked
# AlertLifecycle item, which goes back to Open as soon as the snooze is gone.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecRemoveSnooze.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecRemoveSnooze.ps1 under Modules/' }

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
    function Add-CIPPAzDataTableEntity { param($Context, $TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Context, $TableName, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList, [switch]$GroupList) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CippException { param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPAlertLifecycleKey.ps1')
    . $FunctionPath

    function New-RemoveRequest {
        param($PartitionKey = 'Get-CIPPAlertSomething', $RowKey = 'contoso.onmicrosoft.com-hash123')
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecRemoveSnooze' }
            Headers = @{ }
            Body    = [pscustomobject]@{ PartitionKey = $PartitionKey; RowKey = $RowKey }
            Query   = [pscustomobject]@{ }
        }
    }
}

Describe 'Invoke-ExecRemoveSnooze' {
    BeforeEach {
        $script:Written = $null
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = $tablename } }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Written = $Entity }
        Mock -CommandName ConvertTo-CIPPODataFilterValue -MockWith { $Value }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($TableName -eq 'AlertSnooze') {
                [pscustomobject]@{ PartitionKey = 'Get-CIPPAlertSomething'; RowKey = 'contoso.onmicrosoft.com-hash123'; Tenant = 'contoso.onmicrosoft.com'; ContentHash = 'hash123' }
            }
        }
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.onmicrosoft.com' }
        }
    }

    It 'removes for an unrestricted caller without a tenant check' {
        $Response = Invoke-ExecRemoveSnooze -Request (New-RemoveRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
        Should -Invoke Get-Tenants -Times 0 -Exactly
    }

    It 'returns the tracked alert item to open once the snooze is gone' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($TableName -eq 'AlertSnooze') {
                [pscustomobject]@{ PartitionKey = 'Get-CIPPAlertSomething'; RowKey = 'contoso.onmicrosoft.com-hash123'; Tenant = 'contoso.onmicrosoft.com'; ContentHash = 'hash123' }
            } else {
                [pscustomobject]@{ PartitionKey = 'contoso.onmicrosoft.com'; RowKey = 'Get-CIPPAlertSomething-hash123'; Status = 'Snoozed'; SnoozedBy = 'ops@contoso.com'; SnoozeUntil = '-1'; SnoozeRowKey = 'contoso.onmicrosoft.com-hash123'; ETag = 'W/"1"' }
            }
        }

        $Response = Invoke-ExecRemoveSnooze -Request (New-RemoveRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'AlertLifecycle' -and $Filter -eq "PartitionKey eq 'contoso.onmicrosoft.com' and RowKey eq 'Get-CIPPAlertSomething-hash123'" }
        $script:Written.Status | Should -Be 'Open'
        $script:Written.SnoozedBy | Should -Be ''
        $script:Written.SnoozeRowKey | Should -Be ''
        $script:Written.Keys | Should -Not -Contain 'ETag'
    }

    It 'leaves a tracked item alone when it is not snoozed' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($TableName -eq 'AlertSnooze') {
                [pscustomobject]@{ PartitionKey = 'Get-CIPPAlertSomething'; RowKey = 'contoso.onmicrosoft.com-hash123'; Tenant = 'contoso.onmicrosoft.com'; ContentHash = 'hash123' }
            } else {
                [pscustomobject]@{ PartitionKey = 'contoso.onmicrosoft.com'; RowKey = 'Get-CIPPAlertSomething-hash123'; Status = 'Resolved' }
            }
        }

        $null = Invoke-ExecRemoveSnooze -Request (New-RemoveRequest) -TriggerMetadata $null

        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'removes for a restricted caller when the row belongs to a tenant in scope' {
        Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }

        $Response = Invoke-ExecRemoveSnooze -Request (New-RemoveRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'refuses a restricted caller when the row belongs to a tenant outside their scope' {
        Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = 'Get-CIPPAlertSomething'; RowKey = 'other.onmicrosoft.com-hash123'; Tenant = 'other.onmicrosoft.com' }
        }
        # Scope-narrowed Get-Tenants: the row's tenant resolves to nothing.
        Mock -CommandName Get-Tenants -MockWith { }

        $Response = Invoke-ExecRemoveSnooze -Request (New-RemoveRequest -RowKey 'other.onmicrosoft.com-hash123') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'refuses a restricted caller when the row does not exist' {
        Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { }

        $Response = Invoke-ExecRemoveSnooze -Request (New-RemoveRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}
