# Pester tests for Invoke-CIPPStandardDisableResourceMailbox
#
# The enabled accounts come from the cached user list. With an empty cache nothing matched, so the
# standard reported every resource mailbox account as already disabled.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardDisableResourceMailbox.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardDisableResourceMailbox.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-CIPPDbRequest { [CmdletBinding()] param($TenantFilter, $Type, $Fields) }
    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams, $Select) }
    function New-GraphBulkRequest { [CmdletBinding()] param($tenantid, $Requests) }
    function Set-CIPPDBCacheUsers { [CmdletBinding()] param($TenantFilter) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath
    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardDisableResourceMailbox' {
    BeforeEach {
        Mock Test-CIPPStandardLicense { $true }
        Mock New-CIPPDbRequest { $script:Users }
        Mock New-ExoRequest { [PSCustomObject]@{ UserPrincipalName = 'room@contoso.com'; DisplayName = 'Room'; RecipientTypeDetails = 'RoomMailbox'; ExternalDirectoryObjectId = 'room-1' } }
        Mock New-GraphBulkRequest { }
        Mock Set-CIPPDBCacheUsers { }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
    }

    It 'reports nothing when the cached user list is empty' {
        $script:Users = @()

        Invoke-CIPPStandardDisableResourceMailbox -Tenant $script:Tenant -Settings @{ remediate = $true; alert = $true; report = $true }

        Should -Invoke Set-CIPPStandardsCompareField -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $message -like '*already disabled*' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*cached user list is empty*' }
    }

    It 'still flags an enabled resource mailbox account when the cache has users' {
        $script:Users = @([PSCustomObject]@{ id = 'room-1'; accountEnabled = $true; onPremisesSyncEnabled = $null; assignedLicenses = @(); userType = 'Member' })

        Invoke-CIPPStandardDisableResourceMailbox -Tenant $script:Tenant -Settings @{ alert = $true }

        Should -Invoke Write-StandardsAlert -Times 1 -Exactly
    }
}
