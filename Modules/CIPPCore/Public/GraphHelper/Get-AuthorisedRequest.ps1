
function Get-AuthorisedRequest {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    Param(
        [string]$TenantID,
        [string]$Uri
    )
    if (!$TenantID) {
        $TenantID = $env:TenantID
    }

    if ($Uri -like 'https://graph.microsoft.com/beta/contracts*' -or $Uri -like '*/customers/*' -or $Uri -eq 'https://graph.microsoft.com/v1.0/me/sendMail' -or $Uri -like '*/tenantRelationships/*' -or $Uri -like '*/security/partner/*') {
        return $true
    }
    $Tenant = Get-Tenants -TenantFilter $TenantID | Where-Object { $_.Excluded -eq $false }

    if ($Tenant) {
        return $true
    } else {
        return $false
    }
}
