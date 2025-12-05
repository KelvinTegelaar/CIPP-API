Function Invoke-ExecNotificationConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $sev = ([pscustomobject]$Request.body.Severity).value -join (',')
    $config = @{
        email             = $Request.body.email
        webhook           = $Request.body.webhook
        onepertenant      = $Request.body.onePerTenant
        logsToInclude     = $Request.body.logsToInclude
        sendtoIntegration = $Request.body.sendtoIntegration
        sev               = $sev
    }
    $Results = Set-cippNotificationConfig @Config
    $body = [pscustomobject]@{'Results' = $Results }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
