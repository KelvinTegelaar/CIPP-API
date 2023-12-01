
function Get-AuthorisedRequest {
    [CmdletBinding()]
    Param(
        [string]$TenantID,
        [string]$Uri
    )
    if (!$TenantID) {
        $TenantID = $env:TenantId
    }
    if ($Uri -like 'https://graph.microsoft.com/beta/contracts*' -or $Uri -like '*/customers/*' -or $Uri -eq 'https://graph.microsoft.com/v1.0/me/sendMail' -or $Uri -like '*/tenantRelationships/*') {
        return $true
    }
    $Tenants = Get-Tenants -IncludeErrors
    $SkipList = Get-Tenants -SkipList
    if (($env:PartnerTenantAvailable -eq $true -and $SkipList.customerId -notcontains $TenantID -and $SkipList.defaultDomainName -notcontains $TenantID) -or (($Tenants.customerId -contains $TenantID -or $Tenants.defaultDomainName -contains $TenantID) -and $TenantID -ne $env:TenantId)) {
        return $true
    } else {
        return $false
    }
}
