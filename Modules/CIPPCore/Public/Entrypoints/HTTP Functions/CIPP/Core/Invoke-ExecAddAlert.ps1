using namespace System.Net

Function Invoke-ExecAddAlert {
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

    $Result = if ($Request.Body.sendEmailNow -or $Request.Body.sendWebhookNow -eq $true -or $Request.Body.writeLog -eq $true) {
        $Title = 'CIPP Notification Test'
        if ($Request.Body.sendEmailNow) {
            $CIPPAlert = @{
                Type        = 'email'
                Title       = $Title
                HTMLContent = $Request.Body.text
            }
            Send-CIPPAlert @CIPPAlert
        }
        if ($Request.Body.sendWebhookNow) {
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
        if ($Request.Body.writeLog) {
            Write-LogMessage -headers $Headers -API 'Alerts' -message $Request.Body.text -Sev $Severity
            'Successfully generated alert.'
        }
    } else {
        Write-LogMessage -headers $Headers -API 'Alerts' -message $Request.Body.text -Sev $Severity
        'Successfully generated alert.'
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Result
        })
}
