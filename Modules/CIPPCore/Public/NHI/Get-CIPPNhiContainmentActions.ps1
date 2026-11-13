function Get-CIPPNhiContainmentActions {
    <#
    .SYNOPSIS
        Returns the catalog of non-human identity (NHI) containment actions.
    .DESCRIPTION
        The single source of truth for what Invoke-CIPPNhiContainment can do, in the shape of the BEC catalog: id,
        label, what it does, impact, whether it is reversible, whether it runs by default, the order it runs in,
        the case section its default targets come from and the parameter that takes explicit targets. Critical
        actions need a typed confirmation from the operator. Release says what releasing the case does with it:
        Reverse undoes it, Keep leaves it in place, Manual is listed for the operator.

        Disabling the service principal stops new tokens, not the access tokens it already holds (an hour by
        default, and app-only tokens are not revoked by Continuous Access Evaluation), so the credential and
        access removals run after it. The frontend renders this list, so labels and descriptions are operator-facing.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{ Id = 'DisableServicePrincipal'; Label = 'Disable the app in this tenant'; Description = 'Disables the service principal so it gets no new tokens, for every user and every credential. Tokens already issued stay valid until they expire (about an hour). A managed identity is disabled in Azure instead: remove it from its resource.'; Impact = 'Critical'; Reversible = $true; DefaultSelected = $true; Order = 1; TargetSource = $null; ParameterName = $null; Release = 'Reverse' }
        [pscustomobject]@{ Id = 'RemoveCredentials'; Label = 'Remove flagged credentials'; Description = 'Deletes the selected secrets and certificates from the enterprise app and app registration (by default the flagged ones: added in the window, by another app, or backdated). Never removes a credential nobody selected or flagged: the app may depend on it.'; Impact = 'Critical'; Reversible = $false; DefaultSelected = $true; Order = 2; TargetSource = 'Credentials'; ParameterName = 'CredentialKeyIds'; Release = 'Manual' }
        [pscustomobject]@{ Id = 'RemoveFederatedCredentials'; Label = 'Remove federated credentials'; Description = 'Deletes the selected federated credentials from the app registration (by default those trusting an unrecognised issuer or another Entra tenant).'; Impact = 'High'; Reversible = $false; DefaultSelected = $false; Order = 3; TargetSource = 'Credentials'; ParameterName = 'FederatedCredentialIds'; Release = 'Manual' }
        [pscustomobject]@{ Id = 'RemoveOwners'; Label = 'Remove owners'; Description = 'Removes the selected owners of the enterprise app and app registration. Every owner can add a credential and act with the app''s access.'; Impact = 'High'; Reversible = $false; DefaultSelected = $false; Order = 4; TargetSource = 'Owners'; ParameterName = 'OwnerIds'; Release = 'Manual' }
        [pscustomobject]@{ Id = 'RevokeAppRoleAssignments'; Label = 'Revoke application permissions'; Description = 'Removes the selected application permissions (by default those granted in the window).'; Impact = 'Critical'; Reversible = $false; DefaultSelected = $false; Order = 5; TargetSource = 'AppRoleAssignments'; ParameterName = 'AppRoleAssignmentIds'; Release = 'Manual' }
        [pscustomobject]@{ Id = 'RevokeDelegatedGrants'; Label = 'Revoke delegated consents'; Description = 'Deletes the selected delegated permission grants: the app loses the access users or an administrator consented to.'; Impact = 'High'; Reversible = $false; DefaultSelected = $false; Order = 6; TargetSource = 'DelegatedGrants'; ParameterName = 'GrantIds'; Release = 'Manual' }
        [pscustomobject]@{ Id = 'RemoveDirectoryRoles'; Label = 'Remove directory roles'; Description = 'Removes the selected directory role assignments held directly by the app.'; Impact = 'Critical'; Reversible = $false; DefaultSelected = $false; Order = 7; TargetSource = 'DirectoryRoles'; ParameterName = 'RoleAssignmentIds'; Release = 'Manual' }
        [pscustomobject]@{ Id = 'ConfirmCompromised'; Label = 'Confirm compromised in Identity Protection'; Description = 'Marks the service principal confirmed compromised, so risk-based Conditional Access for workload identities blocks it. Needs Workload ID Premium.'; Impact = 'High'; Reversible = $false; DefaultSelected = $false; Order = 8; TargetSource = $null; ParameterName = $null; Release = 'Manual' }
        [pscustomobject]@{ Id = 'DisablePersistenceApps'; Label = 'Disable the apps it created or put credentials on'; Description = 'Disables the service principals of the apps this app created, or added a credential or owner to (by default those of the window). Each can keep access after this app is disabled; investigate them too. Microsoft''s and CIPP''s own apps are never disabled: remove the credential they were given instead.'; Impact = 'Critical'; Reversible = $true; DefaultSelected = $false; Order = 10; TargetSource = 'DirectoryActions'; ParameterName = 'PersistenceServicePrincipalIds'; Release = 'Reverse' }
        [pscustomobject]@{ Id = 'RevokeElevation'; Label = 'Revoke the access it granted'; Description = 'Removes the permissions and directory roles this app gave itself, other apps or users (by default the high-impact ones of the window): the app role assignment, the role or PIM eligibility, or only the delegated scopes it added - scopes others consented to stay.'; Impact = 'Critical'; Reversible = $false; DefaultSelected = $false; Order = 11; TargetSource = 'DirectoryActions'; ParameterName = 'ElevationIds'; Release = 'Manual' }
        [pscustomobject]@{ Id = 'LockAppInstanceProperties'; Label = 'Lock app instance properties'; Description = 'Turns on the app instance property lock of an app registered in this tenant, so no organisation it is consented in can add a credential to its copy of the app.'; Impact = 'Medium'; Reversible = $true; DefaultSelected = $false; Order = 9; TargetSource = $null; ParameterName = $null; Release = 'Keep' }
    )
}
