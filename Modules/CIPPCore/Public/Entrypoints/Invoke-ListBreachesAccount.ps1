using namespace System.Net

function Invoke-ListBreachesAccount {
    <#
    .SYNOPSIS
    List data breaches for a specific account or domain
    
    .DESCRIPTION
    Retrieves information about data breaches involving a specific email account or domain using the Have I Been Pwned API
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Security
    Summary: List Breaches Account
    Description: Retrieves data breach information for a specific email account or domain using the Have I Been Pwned API with detailed breach information
    Tags: Security,Breaches,HIBP
    Parameter: account (string) [query] - Email address or domain to check for breaches
    Response: Returns an array of breach objects with the following properties:
    Response: - Name (string): Name of the breached service
    Response: - Title (string): Title of the breach
    Response: - Domain (string): Domain of the breached service
    Response: - BreachDate (string): Date when the breach occurred
    Response: - AddedDate (string): Date when the breach was added to HIBP
    Response: - ModifiedDate (string): Date when the breach was last modified
    Response: - PwnCount (number): Number of accounts affected by the breach
    Response: - Description (string): Description of the breach
    Response: - DataClasses (array): Array of data types that were compromised
    Response: - IsVerified (boolean): Whether the breach has been verified
    Response: - IsFabricated (boolean): Whether the breach is fabricated
    Response: - IsSensitive (boolean): Whether the breach contains sensitive data
    Response: - IsRetired (boolean): Whether the breach is retired
    Response: - IsSpamList (boolean): Whether the breach is a spam list
    Example: [
      {
        "Name": "Adobe",
        "Title": "Adobe",
        "Domain": "adobe.com",
        "BreachDate": "2013-10-04",
        "AddedDate": "2013-12-04T00:00:00Z",
        "ModifiedDate": "2013-12-04T00:00:00Z",
        "PwnCount": 152445165,
        "Description": "In October 2013, 153 million Adobe accounts were breached with each containing an internal ID, username, email, <em>encrypted</em> password and a password hint in plain text.",
        "DataClasses": [
          "Email addresses",
          "Password hints",
          "Passwords",
          "Usernames"
        ],
        "IsVerified": true,
        "IsFabricated": false,
        "IsSensitive": false,
        "IsRetired": false,
        "IsSpamList": false
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $Account = $Request.Query.account

    if ($Account -like '*@*') {
        $Results = Get-HIBPRequest "breachedaccount/$($Account)?truncateResponse=false"
    }
    else {
        $Results = Get-BreachInfo -Domain $Account
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($results)
        })

}
