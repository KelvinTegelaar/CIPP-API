function Push-CIPPStandard {
    param (
        $QueueItem, $TriggerMetadata
    )

    Write-Host "Received queue item for $($QueueItem.Tenant) and standard $($QueueItem.Standard)"
    $Tenant = $QueueItem.Tenant
    $Standard = $QueueItem.Standard
    $Remediate = $QueueItem.Settings.remediate
    $Alert = $QueueItem.Settings.alert
    $AlertLevel = $QueueItem.Settings.alertLevel
    if ($Remediate) {
        $FunctionName = 'Invoke-{0}-Remediate' -f $Standard
        $RemediateFeedback = & $FunctionName -Tenant $Tenant -Settings $QueueItem.Settings
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