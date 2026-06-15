function Invoke-CIPPStandardPWnumberMatchingRequiredState {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    Write-LogMessage -API 'Standards' -tenant $tenant -message 'Passwordless with number matching is now enabled by default.' -sev Info
}
