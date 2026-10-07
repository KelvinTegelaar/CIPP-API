function Invoke-CIPPBaselineCollaborationDomainRestriction {
    <#
    .SYNOPSIS
        CollaborationDomainRestriction executor: writes the B2B invitation allow-list.
    .DESCRIPTION
        Rebuilds the domain policy ON TOP of the carried existing definition so sibling
        settings inside the JSON blob (AutoRedeemPolicy) survive - overwriting the whole
        definition would silently reset them. Allowed and blocked lists are mutually
        exclusive in the portal, so setting the allow-list clears the block-list, exactly
        as the classic wrote it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Desired = @("$($Remediate.allowedDomains)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($Desired.Count -eq 0) { return }

    $Definition = $Current.existingDefinition
    if ($null -eq $Definition) { $Definition = [PSCustomObject]@{} }
    if ($null -eq $Definition.B2BManagementPolicy) {
        $Definition | Add-Member -NotePropertyName 'B2BManagementPolicy' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $Definition.B2BManagementPolicy | Add-Member -NotePropertyName 'InvitationsAllowedAndBlockedDomainsPolicy' -NotePropertyValue ([PSCustomObject]@{
            AllowedDomains = @($Desired)
            BlockedDomains = @()
        }) -Force

    $Body = @{
        displayName           = 'B2BManagementPolicy'
        definition            = @(($Definition | ConvertTo-Json -Depth 10 -Compress))
        isOrganizationDefault = $true
    } | ConvertTo-Json -Depth 10 -Compress

    if (-not [string]::IsNullOrWhiteSpace("$($Current.policyId)")) {
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/policies/b2bManagementPolicies/$($Current.policyId)" -type PATCH -body $Body
    } else {
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/policies/b2bManagementPolicies' -type POST -body $Body
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Restricted B2B collaboration to $($Desired.Count) domain(s)." -Sev 'Info'
}
