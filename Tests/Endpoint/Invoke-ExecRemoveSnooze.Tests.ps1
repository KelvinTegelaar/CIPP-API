# Pester tests for Invoke-ExecRemoveSnooze
#
# The delete is keyed by raw PartitionKey/RowKey, so for restricted callers the endpoint
# reads the row first and only deletes when the row's Tenant resolves through the
# scope-narrowed Get-Tenants. Unrestricted callers keep the direct delete.

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
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList, [switch]$GroupList) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CippException { param($Exception) }

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
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = 'AlertSnooze' } }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName ConvertTo-CIPPODataFilterValue -MockWith { $Value }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = 'Get-CIPPAlertSomething'; RowKey = 'contoso.onmicrosoft.com-hash123'; Tenant = 'contoso.onmicrosoft.com' }
        }
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.onmicrosoft.com' }
        }
    }

    It 'removes directly for an unrestricted caller without reading the row back' {
        $Response = Invoke-ExecRemoveSnooze -Request (New-RemoveRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
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
