using namespace System.Net

Function Invoke-PublicPhishingCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]

    #this has been switched to the external free service by cyberdrain at clone.cipp.app due to extreme numbers of executions if selfhosted.
    param($Request, $TriggerMetadata)
    if ($Request.body.Cloned) {
        Write-AlertMessage -message $Request.body.AlertMessage -sev 'Alert' -tenant $Request.body.TenantId
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = 'OK'
        })
}
