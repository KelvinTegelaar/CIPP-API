function Invoke-ExecAddAlert {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter ?? $env:TenantID

    $Severity = 'Alert'

    $Result = if ($Request.Body.sendEmailNow -or $Request.Body.sendWebhookNow -eq $true -or $Request.Body.writeLog -eq $true -or $Request.Body.sendPsaNow -eq $true) {
        $Title = 'CIPP Notification Test'
        if ($Request.Body.sendEmailNow -eq $true) {
            $CIPPAlert = @{
                Type         = 'email'
                Title        = $Title
                HTMLContent  = $Request.Body.text
                TenantFilter = $TenantFilter
            }
            Send-CIPPAlert @CIPPAlert
        }
        if ($Request.Body.sendWebhookNow -eq $true) {
            $JSONContent = @{
                Title = $Title
                Text  = $Request.Body.text
            } | ConvertTo-Json -Compress
            $CIPPAlert = @{
                Type            = 'webhook'
                Title           = $Title
                JSONContent     = $JSONContent
                TenantFilter    = $TenantFilter
                InvokingCommand = 'Invoke-ExecAddAlert'
            }
            Send-CIPPAlert @CIPPAlert
        }
        if ($Request.Body.sendPsaNow -eq $true) {
            $CIPPAlert = @{
                Type         = 'psa'
                Title        = $Title
                HTMLContent  = $Request.Body.text
                TenantFilter = $TenantFilter
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
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Result
        })
}
