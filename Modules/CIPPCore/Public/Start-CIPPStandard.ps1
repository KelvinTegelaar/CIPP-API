function Start-CIPPStandard {
    param (
        $Tenant,
        $Standard,
        $Remediate,
        $Alert,
        $AlertLevel
    )
    
    if ($Remediate) {
        $FunctionName = 'Invoke-{0}-Remediate' -f $Standard
        $RemediateFeedback = & $FunctionName -Tenant $Tenant
        if ($RemediateFeedback -eq 'Good') {
            $AddedText = 'but we remediated this.'
        } else {
            $AddedText = 'and we failed to remediate this.'
        }
    }
    
    if ($Alert) {
        $FunctionName = 'Invoke-{0}-Alert' -f $Standard
        $AlertFeedback = & $FunctionName -Tenant $Tenant
        $AlertText = "The standard $($Standard) is not in the expected state. The alert was $AlertFeedback. $AddedText"
        Write-LogMessage -API "Standards_$($Standard)" -tenant $tenant -message $AlertText -sev $AlertLevel
    }
}