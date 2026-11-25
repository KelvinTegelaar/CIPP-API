function Get-CIPPDefenderIndicator {
    <#
    .SYNOPSIS
        Reads every Microsoft Defender for Endpoint custom indicator in a tenant
    .DESCRIPTION
        Pages through /api/indicators with $top and $skip, because Defender returns no continuation link on this route,
        and stops at the first short page. Emits one slim hashtable per indicator. Throws when any page fails, so a
        caller never acts on a partial list.
    .PARAMETER TenantFilter
        The tenant to read indicators from
    .PARAMETER PageSize
        Indicators per request, up to Defender's maximum of 10000
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [ValidateRange(1, 10000)]
        [int]$PageSize = 10000
    )

    $Skip = 0
    do {
        $Page = @(New-GraphGetRequest -uri "https://api.securitycenter.microsoft.com/api/indicators?`$top=$PageSize&`$skip=$Skip" -tenantid $TenantFilter -scope 'https://api.securitycenter.microsoft.com/.default' -AsApp $true -noPagination $true)
        foreach ($Indicator in $Page) {
            if (-not $Indicator.id) { throw 'Defender returned an indicator without an id' }
            @{
                id                      = "$($Indicator.id)"
                indicatorValue          = $Indicator.indicatorValue
                indicatorType           = $Indicator.indicatorType
                action                  = $Indicator.action
                title                   = $Indicator.title
                description             = $Indicator.description
                severity                = $Indicator.severity
                generateAlert           = $Indicator.generateAlert
                expirationTime          = $Indicator.expirationTime
                creationTimeDateTimeUtc = $Indicator.creationTimeDateTimeUtc
                createdByDisplayName    = $Indicator.createdByDisplayName
                createdBySource         = $Indicator.createdBySource
                lastUpdateTime          = $Indicator.lastUpdateTime
                lastUpdatedBy           = $Indicator.lastUpdatedBy
                rbacGroupNames          = $Indicator.rbacGroupNames
                rbacGroupIds            = $Indicator.rbacGroupIds
                application             = $Indicator.application
            }
        }
        $Skip = $Skip + $PageSize
    } while ($Page.Count -eq $PageSize)
}
