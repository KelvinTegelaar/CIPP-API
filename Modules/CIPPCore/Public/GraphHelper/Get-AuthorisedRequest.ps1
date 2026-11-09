
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
    if (!$TenantID) {
        $TenantID = $env:TenantID
    }

    if ($Uri -like 'https://graph.microsoft.com/beta/contracts*' -or $Uri -like '*/customers/*' -or $Uri -eq 'https://graph.microsoft.com/v1.0/me/sendMail' -or $Uri -like '*/tenantRelationships/*' -or $Uri -like '*/security/partner/*' -or $Uri -match '/organization(\?|$)') {
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
