function Invoke-ExecAppApproval {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .DESCRIPTION
        Builds an admin consent URL for every tenant, for the given ApplicationId or the CIPP-SAM application by default. Returns the links only; nothing is granted until someone opens one and consents.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Seems to be an unused endpoint? -Bobby

    $ApplicationId = if ($Request.Query.ApplicationId) { $Request.Query.ApplicationId } else { $env:ApplicationID }
    $Results = Get-Tenants | ForEach-Object {
        [PSCustomObject]@{
            defaultDomainName = $_.defaultDomainName
            link              = "https://login.microsoftonline.com/$($_.customerId)/v2.0/adminconsent?client_id=$ApplicationId&scope=$ApplicationId/.default"
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
