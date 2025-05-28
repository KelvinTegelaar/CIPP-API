using namespace System.Net

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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

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

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
