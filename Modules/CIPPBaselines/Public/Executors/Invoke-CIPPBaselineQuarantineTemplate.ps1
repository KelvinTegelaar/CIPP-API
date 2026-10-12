function Invoke-CIPPBaselineQuarantineTemplate {
    <#
    .SYNOPSIS
        QuarantineTemplate executor: creates or updates the quarantine policy.
    .DESCRIPTION
        One call to Set-CIPPQuarantinePolicy, the same upsert the classic and the quarantine
        UI use, with the action picked from what the hook found. The permissions hashtable
        is rebuilt from the GRADED Expected-side values on the Current row - the hook and
        this executor must agree on the wire shape, and PermissionToViewHeader/Download stay
        false because Exchange ignores them.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $PolicyName = "$($Current.policyName)"
    if ([string]::IsNullOrWhiteSpace($PolicyName)) { return }

    $ReleaseAction = "$($Remediate.releaseAction)"
    $Permissions = @{
        PermissionToViewHeader     = $false
        PermissionToDownload       = $false
        PermissionToBlockSender    = [bool]($Remediate.permissionToBlockSender -eq $true)
        PermissionToDelete         = [bool]($Remediate.permissionToDelete -eq $true)
        PermissionToPreview        = [bool]($Remediate.permissionToPreview -eq $true)
        PermissionToRelease        = [bool]($ReleaseAction -eq 'PermissionToRelease')
        PermissionToRequestRelease = [bool]($ReleaseAction -eq 'PermissionToRequestRelease')
        PermissionToAllowSender    = [bool]($Remediate.permissionToAllowSender -eq $true)
    }

    $Params = @{
        identity                                = $PolicyName
        action                                  = $(if ($Current.deployed -eq $true) { 'Update' } else { 'Create' })
        EndUserQuarantinePermissions            = $Permissions
        ESNEnabled                              = [bool]($Remediate.esnEnabled -eq $true)
        IncludeMessagesFromBlockedSenderAddress = [bool]($Remediate.includeMessagesFromBlockedSenderAddress -eq $true)
        tenantFilter                            = $TenantFilter
        APIName                                 = 'Baselines'
    }
    Set-CIPPQuarantinePolicy @Params
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "$($Params.action)d quarantine policy '$PolicyName'." -Sev 'Info'
}
