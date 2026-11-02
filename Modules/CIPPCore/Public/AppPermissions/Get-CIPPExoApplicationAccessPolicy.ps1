function Get-CIPPExoApplicationAccessPolicy {
    <#
    .SYNOPSIS
        Reads the Exchange application access policies of a tenant
    .DESCRIPTION
        Application access policies limit which mailboxes an app reaches with the mailbox permissions it holds in
        Entra (Graph, EWS and Outlook REST): RestrictAccess allows only the members of a group, DenyAccess every
        mailbox but them. They do not limit Exchange RBAC for Applications roles. Returns one row per policy and app
        (a policy can name several apps, or '*' for every app) with the access right, the group and whether Exchange
        considers the policy valid. Errors are thrown.
    .PARAMETER TenantFilter
        The tenant to read
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    foreach ($Policy in @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ApplicationAccessPolicy')) {
        foreach ($AppId in @($Policy.AppId)) {
            if (-not $AppId) { continue }
            [PSCustomObject]@{
                # One row per app: the cache keys rows on id.
                id               = '{0}|{1}' -f $Policy.Identity, $AppId
                policyIdentity   = [string]$Policy.Identity
                appId            = [string]$AppId
                accessRight      = [string]$Policy.AccessRight
                scopeName        = [string]$Policy.ScopeName
                scopeIdentity    = [string]$Policy.ScopeIdentity
                scopeIdentityRaw = [string]$Policy.ScopeIdentityRaw
                description      = [string]$Policy.Description
                isValid          = $Policy.IsValid
            }
        }
    }
}
