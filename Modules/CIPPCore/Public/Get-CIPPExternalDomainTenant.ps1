function Get-CIPPExternalDomainTenant {
    <#
    .SYNOPSIS
        Resolves the domains of external (#EXT#) users to their home tenant ids.
    .DESCRIPTION
        Graph user objects carry no home tenant id (identities[].issuer is 'ExternalAzureAD' or the
        host domain), so the #EXT# UPN domain stands in for it (wrong if the guest redeemed with
        another identity). Returns Lookup (domain -> tenant id), Unresolved (domains whose lookup
        failed for any reason other than "not an Entra tenant", so a caller can avoid a definite
        verdict) and Error (the message of a thrown batch, if any).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        [string[]]$Domains,
        [Parameter(Mandatory = $true)]
        $TenantFilter
    )
    $Lookup = @{}
    $Unresolved = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Domains | Where-Object { $_ }), [System.StringComparer]::OrdinalIgnoreCase)
    $ErrorMessage = $null

    if ($Unresolved.Count -gt 0) {
        $Requests = foreach ($Domain in $Unresolved) {
            @{ id = $Domain; method = 'GET'; url = "tenantRelationships/findTenantInformationByDomainName(domainName='$Domain')" }
        }
        try {
            foreach ($Result in @(New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $true)) {
                $Domain = [string]$Result.id
                if ($Result.status -eq 200 -and $Result.body.tenantId) {
                    $Lookup[$Domain] = [string]$Result.body.tenantId
                    [void]$Unresolved.Remove($Domain)
                } elseif ($Result.status -in 400, 404) {
                    # Not an Entra tenant: a definite "no home tenant", not a failure
                    [void]$Unresolved.Remove($Domain)
                }
            }
        } catch {
            $ErrorMessage = $_.Exception.Message
        }
    }

    [pscustomobject]@{
        Lookup     = $Lookup
        Unresolved = $Unresolved
        Error      = $ErrorMessage
    }
}
