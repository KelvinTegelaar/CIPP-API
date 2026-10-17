# Saving custom DKIM selectors from Domain Health is a write on the Domains row, so it is gated
# on the Tenant.DomainAnalyser.ReadWrite permission - not on the literal 'admin'/'editor' role
# names. The role-name check let superadmins and custom roles run the lookup while silently
# never saving their selectors (issue #898).

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-ListDomainHealth.ps1'

    # The endpoint references the unqualified [HttpStatusCode], which only resolves in the
    # Functions host. Register it as a type accelerator so the source parses here too.
    if (-not ('HttpStatusCode' -as [type])) {
        ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
            $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    # The endpoint imports the DNSHealth module up front; the one DNS helper this path needs
    # (Read-DkimRecord) is stubbed below, so the import itself is a no-op here.
    function Import-Module { param([Parameter(Position = 0)]$Name, [switch]$Force) }
    function Get-CIPPTable { param($tablename, $Table) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Set-DnsResolver { param($Resolver) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList, [switch]$GroupList) }
    function Select-CippAllowedTenantData { param([Parameter(ValueFromPipeline)]$InputObject, $TenantProperty) process { $InputObject } }
    function Get-CippRequestAllowedPermissions { }
    function Read-DkimRecord { param($Domain, $Selectors, [switch]$FallbackToMicrosoftSelectors) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    function New-DkimRequest {
        param($Selector)
        $Query = @{ Action = 'ReadDkimRecord'; Domain = 'contoso.com' }
        if ($Selector) { $Query.Selector = $Selector }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListDomainHealth' }
            Headers = @{}
            Query   = $Query
        }
    }
}

Describe 'Invoke-ListDomainHealth - saving custom DKIM selectors' {
    BeforeEach {
        $script:Saved = $null
        $script:DomainRow = [pscustomobject]@{ RowKey = 'contoso.com'; PartitionKey = 'TenantDomains'; TenantId = 'tenant-1'; DkimSelectors = '["selector1"]' }

        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = ($tablename ?? $Table) } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Context -eq 'Config') { [pscustomobject]@{ Resolver = 'Google' } } else { $script:DomainRow }
        }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Saved = $Entity }
        Mock -CommandName Set-DnsResolver -MockWith { }
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
        Mock -CommandName Read-DkimRecord -MockWith { [pscustomobject]@{ Domain = $Domain; Selectors = @($Selectors) } }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'saves the selectors when the caller holds Tenant.DomainAnalyser.ReadWrite' {
        # superadmin resolves to every permission; a custom role resolves to exactly what it grants.
        # Either way the endpoint only sees the permission list, never the role name.
        Mock -CommandName Get-CippRequestAllowedPermissions -MockWith { @('Tenant.DomainAnalyser.Read', 'Tenant.DomainAnalyser.ReadWrite') }

        $Response = Invoke-ListDomainHealth -Request (New-DkimRequest -Selector 'custom1, custom2') -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $script:Saved | Should -Not -BeNullOrEmpty
        $script:Saved.RowKey | Should -Be 'contoso.com'
        $script:Saved.DkimSelectors | Should -Be '["custom1","custom2"]'
        Should -Invoke -CommandName Read-DkimRecord -Times 1 -Exactly -ParameterFilter { @($Selectors) -join ',' -eq 'custom1,custom2' }
    }

    It 'creates a ManualEntry row for an unknown domain when the caller may write' {
        $script:DomainRow = $null
        Mock -CommandName Get-CippRequestAllowedPermissions -MockWith { @('Tenant.DomainAnalyser.ReadWrite') }

        $null = Invoke-ListDomainHealth -Request (New-DkimRequest -Selector 'custom1') -TriggerMetadata $null

        $script:Saved | Should -Not -BeNullOrEmpty
        $script:Saved.PartitionKey | Should -Be 'ManualEntry'
        $script:Saved.RowKey | Should -Be 'contoso.com'
        # A single selector serialises as a bare JSON string rather than a one-element array;
        # every reader goes through ConvertFrom-Json, so assert on the parsed value, not the shape.
        @($script:Saved.DkimSelectors | ConvertFrom-Json) | Should -Be @('custom1')
    }

    It 'still runs the lookup but saves nothing for a read-only caller' {
        Mock -CommandName Get-CippRequestAllowedPermissions -MockWith { @('Tenant.DomainAnalyser.Read') }

        $Response = Invoke-ListDomainHealth -Request (New-DkimRequest -Selector 'custom1') -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $script:Saved | Should -BeNullOrEmpty
        Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke -CommandName Read-DkimRecord -Times 1 -Exactly -ParameterFilter { @($Selectors) -join ',' -eq 'custom1' }
    }

    It 'saves nothing when the caller holds no permissions at all' {
        Mock -CommandName Get-CippRequestAllowedPermissions -MockWith { @() }

        $null = Invoke-ListDomainHealth -Request (New-DkimRequest -Selector 'custom1') -TriggerMetadata $null

        Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'does not let a tenant-restricted writer persist selectors onto an out-of-scope row' {
        Mock -CommandName Get-CippRequestAllowedPermissions -MockWith { @('Tenant.DomainAnalyser.ReadWrite') }
        Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-2') }
        Mock -CommandName Select-CippAllowedTenantData -MockWith { }

        $null = Invoke-ListDomainHealth -Request (New-DkimRequest -Selector 'custom1') -TriggerMetadata $null

        Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'falls back to the stored selectors when none are supplied, without writing' {
        Mock -CommandName Get-CippRequestAllowedPermissions -MockWith { @('Tenant.DomainAnalyser.ReadWrite') }

        $null = Invoke-ListDomainHealth -Request (New-DkimRequest) -TriggerMetadata $null

        Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke -CommandName Read-DkimRecord -Times 1 -Exactly -ParameterFilter { @($Selectors) -join ',' -eq 'selector1' }
    }
}
