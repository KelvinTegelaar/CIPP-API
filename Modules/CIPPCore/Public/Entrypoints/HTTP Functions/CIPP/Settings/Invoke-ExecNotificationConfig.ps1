using namespace System.Net

function Invoke-ExecNotificationConfig {
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

    $sev = ([pscustomobject]$Request.Body.Severity).value -join (',')
    $config = @{
        email             = $Request.Body.email
        webhook           = $Request.Body.webhook
        onepertenant      = $Request.Body.onePerTenant
        logsToInclude     = $Request.Body.logsToInclude
        sendtoIntegration = $Request.Body.sendtoIntegration
        sev               = $sev
    }
    $Results = Set-cippNotificationConfig @Config

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = $Results }
    }
}
