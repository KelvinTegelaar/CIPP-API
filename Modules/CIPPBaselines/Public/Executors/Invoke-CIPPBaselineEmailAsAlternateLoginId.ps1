function Invoke-CIPPBaselineEmailAsAlternateLoginId {
    <#
    .SYNOPSIS
        EmailAsAlternateLoginId executor: writes the org-default HRD policy's
        AlternateIdLogin flag.
    .DESCRIPTION
        PATCHes the existing org-default policy or POSTs a new one - the classic's write,
        with the definition rebuilt whole because HRD definitions are JSON strings that only
        round-trip as a unit.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Enabled = [bool]($Remediate.enabled -eq $true -or "$($Remediate.enabled)" -eq 'True')
    $Definition = @{ HomeRealmDiscoveryPolicy = @{ AlternateIdLogin = @{ Enabled = $Enabled } } } | ConvertTo-Json -Depth 10 -Compress
    $Body = @{ definition = @($Definition); isOrganizationDefault = $true; displayName = 'HomeRealmDiscoveryPolicy' } | ConvertTo-Json -Depth 10 -Compress

    if (-not [string]::IsNullOrWhiteSpace("$($Current.policyId)")) {
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/v1.0/policies/homeRealmDiscoveryPolicies/$($Current.policyId)" -type PATCH -body $Body
    } else {
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/v1.0/policies/homeRealmDiscoveryPolicies' -type POST -body $Body
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set email as alternate login ID to $Enabled." -Sev 'Info'
}
