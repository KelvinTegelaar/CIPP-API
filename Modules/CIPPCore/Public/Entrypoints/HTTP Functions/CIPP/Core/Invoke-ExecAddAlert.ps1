using namespace System.Net

Function Invoke-ExecAddAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    if ($Request.Body.sendEmailNow) {
        $CIPPAlert = @{
            Type         = 'email'
            Title        = 'Test Email Alert'
            HTMLContent  = 'This is a test from CIPP'
            TenantFilter = 'PartnerTenant'
        }
        $Result = Send-CIPPAlert @CIPPAlert
    } else {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API 'Alerts' -message $request.body.text -Sev $request.body.Severity
        $Result = 'Successfully generated alert.'
        # Associate values to output bindings by calling 'Push-OutputBinding'.
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Result
        })
}
