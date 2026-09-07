Function Invoke-ExecNotificationConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $sev = ([pscustomobject]$Request.body.Severity).value -join (',')
    $config = @{
        email                  = $Request.body.email
        webhook                = $Request.body.webhook
        webhookAuthType        = $Request.body.webhookAuthType.value
        webhookAuthToken       = $Request.body.webhookAuthToken
        webhookAuthUsername    = $Request.body.webhookAuthUsername
        webhookAuthPassword    = $Request.body.webhookAuthPassword
        webhookAuthHeaderName  = $Request.body.webhookAuthHeaderName
        webhookAuthHeaderValue = $Request.body.webhookAuthHeaderValue
        webhookAuthHeaders     = $Request.body.webhookAuthHeaders
        onepertenant           = $Request.body.onePerTenant
        logsToInclude          = $Request.body.logsToInclude
        sendtoIntegration      = $Request.body.sendtoIntegration
        UseStandardizedSchema  = [boolean]$Request.body.UseStandardizedSchema
        sev                    = $sev
    }
    $Results = Set-cippNotificationConfig @Config
    if ($Results -like 'Failed*') {
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Results -Sev 'Error'
    } else {
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Results -Sev 'Info'
    }
    $body = [pscustomobject]@{'Results' = $Results }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
