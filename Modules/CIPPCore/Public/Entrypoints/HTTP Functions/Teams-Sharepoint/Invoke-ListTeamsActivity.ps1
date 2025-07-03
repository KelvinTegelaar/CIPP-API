using namespace System.Net

function Invoke-ListTeamsActivity {
    <#
    .SYNOPSIS
    List Microsoft Teams activity reports for users
    
    .DESCRIPTION
    Retrieves Microsoft Teams activity reports for users including chat messages, calls, and meetings using Microsoft Graph API
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Activity.Read
        
    .NOTES
    Group: Teams & SharePoint
    Summary: List Teams Activity
    Description: Retrieves Microsoft Teams activity reports for users including chat messages, calls, and meetings using Microsoft Graph API with 30-day period reporting
    Tags: Teams,Activity,Reports,Graph API
    Parameter: tenantFilter (string) [query] - Target tenant identifier
    Parameter: Type (string) [query] - Activity report type (e.g., TeamsUserActivity)
    Response: Returns an array of Teams activity objects with the following properties:
    Response: - UPN (string): User Principal Name
    Response: - LastActive (string): Last activity date
    Response: - TeamsChat (string): Team chat message count
    Response: - CallCount (string): Call count
    Response: - MeetingCount (string): Meeting count
    Example: [
      {
        "UPN": "john.doe@contoso.com",
        "LastActive": "2024-01-20",
        "TeamsChat": "45",
        "CallCount": "12",
        "MeetingCount": "8"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $type = $request.Query.Type
    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/get$($type)Detail(period='D30')" -tenantid $TenantFilter | ConvertFrom-Csv | Select-Object @{ Name = 'UPN'; Expression = { $_.'User Principal Name' } },
    @{ Name = 'LastActive'; Expression = { $_.'Last Activity Date' } },
    @{ Name = 'TeamsChat'; Expression = { $_.'Team Chat Message Count' } },
    @{ Name = 'CallCount'; Expression = { $_.'Call Count' } },
    @{ Name = 'MeetingCount'; Expression = { $_.'Meeting Count' } }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
