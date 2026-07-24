function Get-CIPPAlertInactiveTeamsSites {
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

    $HasTeams = Test-CIPPStandardLicense -StandardName 'InactiveTeamsSites' -TenantFilter $TenantFilter -Preset Teams
    if (-not $HasTeams) {
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
            if ($Site.siteType -ne 'SharePointAndTeams') { continue }

            $LastActivity = $Site.effectiveLastActivityDate
            if (-not $LastActivity) {
                if (-not $IncludeNeverActive) { continue }
            } elseif ([datetime]$LastActivity -gt $Lookup) {
                continue
            }

            $TeamsSiteUrl = $Site.webUrl
            $TeamsSiteLabel = $Site.teamsTeamName ?? $Site.displayName ?? $TeamsSiteUrl
            if ([string]::IsNullOrWhiteSpace($TeamsSiteLabel) -and $Site.ownerDisplayName) {
                $TeamsSiteLabel = $Site.ownerDisplayName
            }

            $LastActivityDisplay = if ($LastActivity) { $LastActivity } else { 'Never' }
            $DaysSinceActivityValue = if ($LastActivity) {
                [Math]::Round(((Get-Date).Date - [datetime]$LastActivity).TotalDays)
            } else {
                'N/A'
            }

            $OwnerPart = if ($Site.ownerPrincipalName) { " Owner: $($Site.ownerPrincipalName)." } else { '' }
            $Message = "TeamsSite '$TeamsSiteLabel' ($TeamsSiteUrl) Teams last active $LastActivityDisplay.$OwnerPart"

            [PSCustomObject]@{
                Message                   = $Message
                Id                        = $Site.siteId
                siteId                    = $Site.siteId
                teamsSiteName             = $TeamsSiteLabel
                teamsSiteUrl              = $TeamsSiteUrl
                teamsTeamId               = $Site.teamsTeamId
                teamsTeamName             = $Site.teamsTeamName
                teamsLastActivityDate     = $LastActivityDisplay
                DaysSinceActivity         = $DaysSinceActivityValue
                sharePointLastActivityDate = $Site.sharePointLastActivityDate
                effectiveLastActivityDate = $Site.effectiveLastActivityDate
                ownerPrincipalName        = $Site.ownerPrincipalName
                teamLinkResolutionStatus  = $Site.teamLinkResolutionStatus
                cachedAt                  = $Site.cachedAt
                reportPeriod              = $Site.reportPeriod
                Tenant                    = $TenantFilter
            }
        }

        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-AlertMessage -message "Inactive TeamsSite alert failed: $($ErrorMessage.NormalizedError)" -tenant $TenantFilter -LogData $ErrorMessage
    }
}
