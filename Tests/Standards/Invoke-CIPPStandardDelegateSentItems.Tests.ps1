# Pester tests for Invoke-CIPPStandardDelegateSentItems
#
# The mailboxes to check come from the cached mailbox list. With an empty cache nothing was
# non-compliant, so the standard reported "Configured correctly".

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardDelegateSentItems.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardDelegateSentItems.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-CippDbRequest { [CmdletBinding()] param($TenantFilter, $Type, $Fields) }
    function New-ExoBulkRequest { [CmdletBinding()] param($tenantid, $cmdletArray) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath
    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardDelegateSentItems' {
    BeforeEach {
        Mock Test-CIPPStandardLicense { $true }
        Mock New-CippDbRequest { $script:Mailboxes }
        Mock New-ExoBulkRequest { }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
    }

    It 'reports nothing when the cached mailbox list is empty' {
        $script:Mailboxes = @()

        Invoke-CIPPStandardDelegateSentItems -Tenant $script:Tenant -Settings @{ remediate = $true; alert = $true; report = $true }

        Should -Invoke Set-CIPPStandardsCompareField -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $message -like '*enabled*' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*cached mailbox list is empty*' }
    }

    It 'reports configured correctly when every cached mailbox has the setting on' {
        $script:Mailboxes = @([PSCustomObject]@{ UPN = 'shared@contoso.com'; recipientTypeDetails = 'SharedMailbox'; MessageCopyForSendOnBehalfEnabled = $true; MessageCopyForSentAsEnabled = $true })

        Invoke-CIPPStandardDelegateSentItems -Tenant $script:Tenant -Settings @{ report = $true }

        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter { $CurrentValue.state -eq 'Configured correctly' }
    }
}
