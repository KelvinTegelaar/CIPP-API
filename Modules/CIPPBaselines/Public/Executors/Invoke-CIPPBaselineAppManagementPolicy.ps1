function Invoke-CIPPBaselineAppManagementPolicy {
    <#
    .SYNOPSIS
        AppManagementPolicy executor: patches the default app management policy.
    .DESCRIPTION
        The PATCH body is the hook's desired state verbatim - the graded expected and the
        write are the same object by construction, so there is nothing to rebuild here.
        App-only, v1.0, matching the classic's write.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    if (-not $Current.desiredState) { return }
    $Body = ConvertTo-Json -Compress -Depth 20 -InputObject $Current.desiredState
    $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/v1.0/policies/defaultAppManagementPolicy' -type PATCH -body $Body -AsApp $true
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Updated the default app management policy credential restrictions.' -Sev 'Info'
}
