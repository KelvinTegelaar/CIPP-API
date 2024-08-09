using namespace System.Net

Function Invoke-PublicPhishingCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    if ($Request.body.Cloned) {
        $AlertMessage = If ($Request.body.headers.referer) {
            "Potential Phishing page detected. Detected Information: Hosted at $($Request.headers.referer). Access by IP $($request.headers.'x-forwarded-for')"
        } else {
            "Potential Phishing page detected. Detected Information:  Access by IP $($request.headers.'x-forwarded-for')"
        }
        Write-AlertMessage -message $AlertMessage -sev 'Alert' -tenant $Request.body.TenantId
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = 'OK'
        })
}
