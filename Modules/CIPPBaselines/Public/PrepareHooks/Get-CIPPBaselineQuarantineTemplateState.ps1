function Get-CIPPBaselineQuarantineTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for QuarantineTemplate: is this instance's quarantine policy deployed
        and in sync.
    .DESCRIPTION
        One instance is one POLICY CONFIGURATION, keyed on its display name - this family
        has no templates table at all; the settings ARE the baseline variables. The classic
        was already MULTIPLE:True with the same per-policy shape.

        The graded fields are the classic's: ESNEnabled,
        IncludeMessagesFromBlockedSenderAddress, and the six end-user permissions.
        PermissionToViewHeader and PermissionToDownload are forced false on both sides -
        the classic's comment records that Exchange ignores the values.

        Permissions are graded PER KEY where the classic compared the unordered value
        multisets - two policies that swapped which permissions were on could read equal
        there. Per-key is what Set-CIPPQuarantinePolicy actually writes, so the compare and
        the write agree.

        The default quarantine policies carry the all-zeros Guid and are never adopted. Exchange
        refuses to create or edit a policy with a default's name, so that is a config error.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoQuarantinePolicy')
    if ($Policies.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoQuarantinePolicy')) {
        return @{ Current = $null }
    }
    $BuiltInPolicyNames = $Policies.Where({ "$($_.Guid)" -eq '00000000-0000-0000-0000-000000000000' }).Name
    $Policies = @($Policies.Where({ "$($_.Guid)" -ne '00000000-0000-0000-0000-000000000000' }))

    $V = $Item.Variables
    $PolicyName = $V.displayName
    if ($PolicyName -is [System.Management.Automation.PSCustomObject] -and $PolicyName.PSObject.Properties.Name -contains 'value') { $PolicyName = $PolicyName.value }
    $PolicyName = "$PolicyName"
    if ([string]::IsNullOrWhiteSpace($PolicyName)) { return @{ Current = $null; ConfigError = $true } }
    # Exchange refuses to create or edit a built-in policy, so a deploy could never succeed
    if ($PolicyName -in $BuiltInPolicyNames) {
        return @{ Current = $null; ConfigError = $true; NoDataReason = "$PolicyName is a built-in Microsoft quarantine policy that cannot be created or edited. Give the policy a custom name" }
    }

    $ReleaseAction = "$($V.ReleaseAction)"
    if ($V.ReleaseAction -is [System.Management.Automation.PSCustomObject] -and $V.ReleaseAction.PSObject.Properties.Name -contains 'value') { $ReleaseAction = "$($V.ReleaseAction.value)" }

    $Expected = [PSCustomObject]@{
        deployed                                = $true
        esnEnabled                              = [bool]($V.ESNEnabled -eq $true)
        includeMessagesFromBlockedSenderAddress = [bool]($V.IncludeMessagesFromBlockedSenderAddress -eq $true)
        permissionToViewHeader                  = $false
        permissionToDownload                    = $false
        permissionToBlockSender                 = [bool]($V.PermissionToBlockSender -eq $true)
        permissionToDelete                      = [bool]($V.PermissionToDelete -eq $true)
        permissionToPreview                     = [bool]($V.PermissionToPreview -eq $true)
        permissionToRelease                     = [bool]($ReleaseAction -eq 'PermissionToRelease')
        permissionToRequestRelease              = [bool]($ReleaseAction -eq 'PermissionToRequestRelease')
        permissionToAllowSender                 = [bool]($V.PermissionToAllowSender -eq $true)
    }

    $Existing = $Policies | Where-Object { "$($_.Name)" -eq $PolicyName } | Select-Object -First 1
    if (-not $Existing) {
        $Current = [PSCustomObject]@{ deployed = $false }
        $Current | Add-Member -NotePropertyName 'policyName' -NotePropertyValue $PolicyName
        return @{
            Expected = [PSCustomObject]@{ deployed = $true }
            Current  = $Current
        }
    }

    # The tenant stores permissions as an encoded value; the same helper the classic used
    # decodes it back to the per-key booleans.
    $ExistingPermissions = try {
        Convert-QuarantinePermissionsValue -InputObject $Existing.EndUserQuarantinePermissions -ErrorAction Stop
    } catch {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Could not decode quarantine permissions for policy '$PolicyName': $($_.Exception.Message)" -Sev 'Error'
        return @{ Current = $null }
    }

    $Current = [PSCustomObject]@{
        deployed                                = $true
        esnEnabled                              = [bool]$Existing.ESNEnabled
        includeMessagesFromBlockedSenderAddress = [bool]$Existing.IncludeMessagesFromBlockedSenderAddress
        permissionToViewHeader                  = $false
        permissionToDownload                    = $false
        permissionToBlockSender                 = [bool]$ExistingPermissions.PermissionToBlockSender
        permissionToDelete                      = [bool]$ExistingPermissions.PermissionToDelete
        permissionToPreview                     = [bool]$ExistingPermissions.PermissionToPreview
        permissionToRelease                     = [bool]$ExistingPermissions.PermissionToRelease
        permissionToRequestRelease              = [bool]$ExistingPermissions.PermissionToRequestRelease
        permissionToAllowSender                 = [bool]$ExistingPermissions.PermissionToAllowSender
    }
    $Current | Add-Member -NotePropertyName 'policyName' -NotePropertyValue $PolicyName

    @{ Expected = $Expected; Current = $Current }
}
