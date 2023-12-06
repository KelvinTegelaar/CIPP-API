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
        try {
            $RemediateFeedback = & $FunctionName -Tenant $Tenant
            $AddedText = 'but we remediated this.'
        } catch {
            $AddedText = "but we failed to remediate. Error: $($_.exception.message)"
            $AlertLevel = 'Alert'
        }
    }
    
    if ($Alert) {
        $FunctionName = 'Invoke-{0}-Alert' -f $Standard
        $AlertFeedback = & $FunctionName -Tenant $Tenant
        $AlertText = "The standard $($Standard) is not in the expected state. The alert was $AlertFeedback.  $AddedText"
        $AlertText
        #Generate a cipp log alert based on the setting?
    }

    #Create another case for the reporting functionality?
}