using namespace System.Net

function Invoke-ExecAppApproval {
    <#
    .SYNOPSIS
    Generate admin consent links for application approval across tenants
    
    .DESCRIPTION
    Generates admin consent links for application approval across all tenants, providing URLs for each tenant to grant admin consent to a specified application.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    
    .NOTES
    Group: Application Management
    Summary: Exec App Approval
    Description: Generates admin consent links for application approval across all tenants, providing URLs for each tenant to grant admin consent to a specified application. Useful for bulk application approval scenarios.
    Tags: Application,Admin Consent,Approval,Multi-Tenant
    Parameter: ApplicationId (string) [query/env] - Application ID to generate consent links for
    Response: Returns an array of objects with the following properties:
    Response: - defaultDomainName (string): Tenant domain name
    Response: - link (string): Admin consent URL for the tenant
    Example: [
      {
        "defaultDomainName": "contoso.onmicrosoft.com",
        "link": "https://login.microsoftonline.com/12345678-1234-1234-1234-123456789012/v2.0/adminconsent?client_id=app-id&scope=app-id/.default"
      }
    ]
    Error: Returns error details if the operation fails to generate consent links.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    Write-Host "$($Request.query.ID)"
    # Interact with query parameters or the body of the request.

    $ApplicationId = if ($Request.Query.ApplicationId) { $Request.Query.ApplicationId } else { $env:ApplicationID }
    $Results = Get-Tenants | ForEach-Object {
        [PSCustomObject]@{
            defaultDomainName = $_.defaultDomainName
            link              = "https://login.microsoftonline.com/$($_.customerId)/v2.0/adminconsent?client_id=$ApplicationId&scope=$ApplicationId/.default"
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
