function Get-CIPPAlertInactiveSharePointSites {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    $HasSharePoint = Test-CIPPStandardLicense -StandardName 'InactiveSharePointSites' -TenantFilter $TenantFilter -Preset SharePoint
    if (-not $HasSharePoint) {
        return
    }

    try {
        $DaysSinceActivity = 90
        $IncludeNeverActive = $false

        if ($InputValue -is [hashtable] -or $InputValue -is [PSCustomObject]) {
            if ($null -ne $InputValue.IncludeNeverActive) {
                $IncludeNeverActive = [bool]$InputValue.IncludeNeverActive
            }
            if ($null -ne $InputValue.DaysSinceActivity -and $InputValue.DaysSinceActivity -ne '') {
                $ParsedDays = 0
                if ([int]::TryParse($InputValue.DaysSinceActivity.ToString(), [ref]$ParsedDays) -and $ParsedDays -gt 0) {
                    $DaysSinceActivity = $ParsedDays
                }
            }
        } elseif ($InputValue) {
            $ParsedDays = 0
            if ([int]::TryParse($InputValue.ToString(), [ref]$ParsedDays) -and $ParsedDays -gt 0) {
                $DaysSinceActivity = $ParsedDays
            }
        }

        $Lookup = (Get-Date).AddDays(-$DaysSinceActivity).Date

        $SiteActivityRows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SiteActivity')
        if (-not $SiteActivityRows) {
            return
        }

        $AlertData = foreach ($Site in $SiteActivityRows) {
            if ($Site.isDeleted -eq $true) { continue }
            if ($Site.siteType -ne 'SharePoint') { continue }

            $LastActivity = $Site.effectiveLastActivityDate
            if (-not $LastActivity) {
                if (-not $IncludeNeverActive) { continue }
            } elseif ([DateTime]$LastActivity -gt $Lookup) {
                continue
            }

            $SiteUrl = $Site.webUrl
            $SiteLabel = $Site.displayName ?? $SiteUrl
            if ([string]::IsNullOrWhiteSpace($SiteLabel) -and $Site.ownerDisplayName) {
                $SiteLabel = $Site.ownerDisplayName
            }

            $LastActivityDisplay = if ($LastActivity) { $LastActivity } else { 'Never' }
            $DaysSinceActivityValue = if ($LastActivity) {
                [Math]::Round(((Get-Date).Date - [DateTime]$LastActivity).TotalDays)
            } else {
                'N/A'
            }

            $OwnerPart = if ($Site.ownerPrincipalName) { " Owner: $($Site.ownerPrincipalName)." } else { '' }
            $Message = "Site '$SiteLabel' ($SiteUrl) SharePoint last active $LastActivityDisplay.$OwnerPart"

            [PSCustomObject]@{
                Message               = $Message
                Id                    = $Site.siteId
                siteId                = $Site.siteId
                webUrl                = $SiteUrl
                displayName           = $Site.displayName
                ownerPrincipalName    = $Site.ownerPrincipalName
                lastActivityDate      = $LastActivityDisplay
                DaysSinceActivity     = $DaysSinceActivityValue
                rootWebTemplate       = $Site.rootWebTemplate
                cachedAt              = $Site.cachedAt
                reportPeriod          = $Site.reportPeriod
                teamLinkResolutionStatus = $Site.teamLinkResolutionStatus
                Tenant                = $TenantFilter
            }
        }

        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-AlertMessage -message "Inactive SharePoint sites alert failed: $($ErrorMessage.NormalizedError)" -tenant $TenantFilter -LogData $ErrorMessage
    }
}
