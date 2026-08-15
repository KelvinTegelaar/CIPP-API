function Set-CIPPDBCacheTeamsResourceAccounts {
    <#
    .SYNOPSIS
        Caches Teams resource accounts (Auto Attendant / Call Queue) for a tenant

    .DESCRIPTION
        Walks the paged Teams.PlatformService/v2/ApplicationInstances surface via New-TeamsRequestV2
        (the only surface that returns resource accounts; Graph's admin/teams/userConfigurations does
        not) and writes displayName, userPrincipalName, objectId and applicationId per account into
        the CIPP database under Type 'TeamsResourceAccounts'.

    .PARAMETER TenantFilter
        The tenant to cache Teams resource accounts for

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
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'TeamsResourceAccountsCache' -TenantFilter $TenantFilter -Preset Teams -SkipLog

        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have a Teams license, skipping Teams resource accounts' -sev Debug
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams resource accounts' -sev Debug

        $ResourceAccounts = [System.Collections.Generic.List[object]]::new()
        $SkipToken = $null
        do {
            $QueryParameters = @{ pageSize = 100 }
            if ($SkipToken) { $QueryParameters['skipToken'] = $SkipToken }
            $Page = New-TeamsRequestV2 -TenantFilter $TenantFilter -Path 'Teams.PlatformService/v2/ApplicationInstances' -QueryParameters $QueryParameters
            foreach ($Instance in @($Page.applicationInstances)) {
                if ($null -ne $Instance) {
                    $ResourceAccounts.Add([PSCustomObject]@{
                            displayName       = $Instance.displayName
                            userPrincipalName = $Instance.userPrincipalName
                            objectId          = $Instance.objectId
                            applicationId     = $Instance.applicationId
                        })
                }
            }
            $SkipToken = $Page.skipToken
        } while ($SkipToken)

        if ($ResourceAccounts.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'TeamsResourceAccounts' -Data @($ResourceAccounts) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($ResourceAccounts.Count) Teams resource accounts" -sev Debug
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No Teams resource accounts found' -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams resource accounts: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}
