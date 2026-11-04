function Set-CIPPDBCacheSecureScore {
    <#
    .SYNOPSIS
        Caches secure score history (last 14 days) and control profiles for a tenant

    .PARAMETER TenantFilter
        The tenant to cache secure score for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching secure score' -sev Debug

        # Cache secure score history (last 14 days)
        $SecureScore = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/secureScores?$top=14' -tenantid $TenantFilter -noPagination $true
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SecureScore' -Data $SecureScore -AddCount

        # Cache secure score control profiles
        $Profiles = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/secureScoreControlProfiles' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SecureScoreControlProfiles' -Data $Profiles -AddCount

        # One compact row per tenant for the estate-wide views. The full SecureScore records are ~15 KB
        # each x 14 days; reading those for every tenant is what made the AllTenants page slow. The
        # profiles' description/remediation HTML stays in SecureScoreControlProfiles and loads on demand.
        $Points = @($SecureScore | Where-Object { $_.createdDateTime } | Sort-Object -Property { [datetime]$_.createdDateTime })
        if ($Points.Count -gt 0) {
            $Latest = $Points[-1]
            $ProfileLookup = @{}
            foreach ($ControlProfile in @($Profiles)) { if ($ControlProfile.id) { $ProfileLookup[[string]$ControlProfile.id] = $ControlProfile } }

            $Controls = foreach ($Control in @($Latest.controlScores)) {
                $ControlProfile = $ProfileLookup[[string]$Control.controlName]
                # Same rule as the remediation standard: the latest state update is the effective state.
                $LatestState = @($ControlProfile.controlStateUpdates) | Where-Object { $_ } | Sort-Object updatedDateTime | Select-Object -Last 1
                [PSCustomObject]@{
                    controlName        = $Control.controlName
                    title              = $ControlProfile.title
                    controlCategory    = $Control.controlCategory ?? $ControlProfile.controlCategory
                    tier               = $ControlProfile.tier
                    score              = $Control.score
                    maxScore           = $ControlProfile.maxScore
                    scoreInPercentage  = $Control.scoreInPercentage
                    userImpact         = $ControlProfile.userImpact
                    implementationCost = $ControlProfile.implementationCost
                    threats            = @($ControlProfile.threats)
                    state              = [string]::IsNullOrEmpty($LatestState.state) ? 'Default' : $LatestState.state
                    stateBy            = $LatestState.updatedBy
                    stateDate          = $LatestState.updatedDateTime
                    stateComment       = $LatestState.comment
                }
            }

            $Summary = [PSCustomObject]@{
                id              = 'latest'
                currentScore    = $Latest.currentScore
                maxScore        = $Latest.maxScore
                createdDateTime = $Latest.createdDateTime
                history         = @($Points | ForEach-Object { [PSCustomObject]@{ date = $_.createdDateTime; currentScore = $_.currentScore; maxScore = $_.maxScore } })
                controls        = @($Controls)
            }
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SecureScoreSummary' -Data @($Summary) -AddCount
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached secure score and control profiles successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache secure score: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
