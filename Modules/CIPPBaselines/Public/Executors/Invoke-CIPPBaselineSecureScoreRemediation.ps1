function Invoke-CIPPBaselineSecureScoreRemediation {
    <#
    .SYNOPSIS
        SecureScoreRemediation executor: writes the configured control states.
    .DESCRIPTION
        One bulk request PATCHing each drifted control's state, comment and the Microsoft
        SecureScore vendor block - the classic's exact write. Defender controls (scid_*)
        skip: their state cannot be set through this endpoint, and the classic skipped them
        for the same reason. Per-control failures log and continue.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Controls = @($Current.driftedControls | Where-Object { $_ -and "$($_.Control)" -notmatch '^scid_' })
    $Skipped = @($Current.driftedControls | Where-Object { $_ -and "$($_.Control)" -match '^scid_' })
    foreach ($Skip in $Skipped) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Secure score control '$($Skip.Control)' is a Defender control and cannot be set through this endpoint - skipped." -Sev 'Info'
    }
    if ($Controls.Count -eq 0) { return }

    $Id = 1
    $Requests = @(foreach ($Control in $Controls) {
            @{
                id      = $Id++
                method  = 'PATCH'
                url     = "security/secureScoreControlProfiles/$($Control.Control)"
                body    = @{
                    state             = "$($Control.State)"
                    comment           = "$($Control.Reason)"
                    vendorInformation = @{ vendor = 'Microsoft'; provider = 'SecureScore' }
                }
                headers = @{ 'Content-Type' = 'application/json' }
            }
        })
    $Results = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests)
    $Failures = 0
    for ($i = 0; $i -lt @($Results).Count; $i++) {
        $Result = @($Results)[$i]
        if ($Result.status -notin @(200, 204)) {
            $Failures++
            $ErrorText = $(if ($Result.body.error.message) { "$($Result.body.error.message)" } else { "status $($Result.status)" })
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Secure score control '$($Controls[$i].Control)' write failed: $ErrorText" -Sev 'Error'
        }
    }
    if ($Failures -ge $Controls.Count) { throw "Every secure score control write failed for $TenantFilter - see the log for the first error." }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Secure score: set $($Controls.Count - $Failures) of $($Controls.Count) control state(s)." -Sev 'Info'
}
