
function Get-AuthorisedRequest {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TenantID,
        [string]$Uri
    )
    $Exempt = $false
    if ($Uri) {
        # Partner-level exemptions match the parsed host and path, so anything that could disguise either is refused.
        $Parsed = $null
        if ($Uri.Contains('#') -or $Uri.Split('?')[0] -match '\\|%2e|/\.\.?(/|$)' -or -not [uri]::TryCreate($Uri, [UriKind]::Absolute, [ref]$Parsed)) { return $false }
        $Path = $Parsed.AbsolutePath
        $Exempt = $Parsed.Scheme -eq 'https' -and $(switch ($Parsed.Authority) {
                'graph.microsoft.com' { $Path -match '^/beta/contracts(/|$)|^/v1\.0/me/sendMail$|^/(v1\.0|beta)/(tenantRelationships|security/partner)/|^/(v1\.0|beta)/organization$' }
                # Device batch status URLs are built from a Location header that can add a second slash.
                'api.partnercenter.microsoft.com' { $Path -match '^/v1/+customers/([^/]*)' }
                default { $false }
            })
    }
    if (!$TenantID) {
        # A tenant-restricted caller never acts as the partner tenant, except for Lighthouse reads (the caller filters
        # them to its tenants) and Partner Center calls for a customer in its scope.
        if ($script:CippAllowedTenantsStorage -and $null -ne $script:CippAllowedTenantsStorage.Value) {
            return [bool]($Exempt -and ($Path -match '^/(v1\.0|beta)/tenantRelationships/managedTenants/' -or ($Parsed.Authority -eq 'api.partnercenter.microsoft.com' -and $script:CippAllowedTenantsStorage.Value -contains $Matches[1])))
        }
        $TenantID = $env:TenantID
    }

    if ($Exempt) {
        return $true
    }
    # Every Graph and Exchange call lands here. A tenant once allowed stays allowed for the rest of this invocation:
    # Initialize-CippRequestContext clears the memo per request, Craft per background task, and a change of tenant
    # scope (Assert-CippTenantAccess swaps it briefly) starts a new one.
    $Scope = if ($script:CippAllowedTenantsStorage) { $script:CippAllowedTenantsStorage.Value }
    if (-not $script:CippAuthorisedTenantMemo -or -not [object]::ReferenceEquals($script:CippAuthorisedTenantMemo.Scope, $Scope)) {
        $script:CippAuthorisedTenantMemo = @{ Scope = $Scope; Tenants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
    }
    if ($script:CippAuthorisedTenantMemo.Tenants.Contains($TenantID)) { return $true }

    if (@(Get-Tenants -IncludeErrors -TenantFilter $TenantID).Where({ $_.Excluded -eq $false })) {
        [void]$script:CippAuthorisedTenantMemo.Tenants.Add($TenantID)
        return $true
    }
    return $false
}
