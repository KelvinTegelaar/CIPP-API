using namespace System.Net

function Invoke-ExecAddAlert {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Severity = 'Alert'

    $Result = if ($Request.Body.sendEmailNow -or $Request.Body.sendWebhookNow -eq $true -or $Request.Body.writeLog -eq $true -or $Request.Body.sendPsaNow -eq $true) {
        $sev = ([pscustomobject]$Request.Body.Severity).value -join (',')
        if ($Request.Body.email -or $Request.Body.webhook) {
            Write-Host 'found config, setting'
            $config = @{
                email             = $Request.Body.email
                webhook           = $Request.Body.webhook
                onepertenant      = $Request.Body.onePerTenant
                logsToInclude     = $Request.Body.logsToInclude
                sendtoIntegration = $true
                sev               = $sev
            }
            Write-Host "setting notification config to $($config | ConvertTo-Json)"
            $Results = Set-cippNotificationConfig @Config
            Write-Host $Results
        }
        $Title = 'CIPP Notification Test'
        if ($Request.Body.sendEmailNow -eq $true) {
            $CIPPAlert = @{
                Type        = 'email'
                Title       = $Title
                HTMLContent = $Request.Body.text
            }
            Send-CIPPAlert @CIPPAlert
        }
        if ($Request.Body.sendWebhookNow -eq $true) {
            $JSONContent = @{
                Title = $Title
                Text  = $Request.Body.text
            } | ConvertTo-Json -Compress
            $CIPPAlert = @{
                Type        = 'webhook'
                Title       = $Title
                JSONContent = $JSONContent
            }
            Send-CIPPAlert @CIPPAlert
        }
        if ($Request.Body.sendPsaNow -eq $true) {
            $CIPPAlert = @{
                Type        = 'psa'
                Title       = $Title
                HTMLContent = $Request.Body.text
            }
            Send-CIPPAlert @CIPPAlert
        }

        if ($Request.Body.writeLog -eq $true) {
            Write-LogMessage -headers $Headers -API 'Alerts' -message $Request.Body.text -Sev $Severity
            'Successfully generated alert.'
        }
    } else {
        Write-LogMessage -headers $Headers -API 'Alerts' -message $Request.Body.text -Sev $Severity
        'Successfully generated alert.'
    }
    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Result
    }
}
