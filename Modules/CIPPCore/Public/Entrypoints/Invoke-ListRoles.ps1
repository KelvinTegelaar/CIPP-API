using namespace System.Net

function Invoke-ListRoles {
    <#
    .SYNOPSIS
    List directory roles and their members
    
    .DESCRIPTION
    Retrieves directory roles and their members from Microsoft Graph API, including role descriptions and member details.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.Read
        
    .NOTES
    Group: Identity Management
    Summary: List Roles
    Description: Retrieves directory roles and their members from Microsoft Graph API, including role descriptions and member details with display names and user principal names.
    Tags: Identity,Roles,Directory,Graph API
    Parameter: tenantFilter (string) [query] - Target tenant identifier
    Response: Returns an array of role objects with the following properties:
    Response: - DisplayName (string): Role display name
    Response: - Description (string): Role description
    Response: - Members (string): Comma-separated list of members with display names and user principal names
    Example: [
      {
        "DisplayName": "Global Administrator",
        "Description": "Can manage all aspects of Azure AD and Microsoft services that use Azure AD identities.",
        "Members": " John Doe (john.doe@contoso.com), Jane Smith (jane.smith@contoso.com)"
      },
      {
        "DisplayName": "User Administrator",
        "Description": "Can manage all aspects of users and groups.",
        "Members": "none"
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
    $SelectList = 'id', 'displayName', 'userPrincipalName'

    [System.Collections.Generic.List[PSCustomObject]]$Roles = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles?`$expand=members" -tenantid $TenantFilter
    $GraphRequest = foreach ($Role in $Roles) {

        #[System.Collections.Generic.List[PSCustomObject]]$Members = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directoryRoles/$($Role.id)/members?`$select=$($SelectList -join ',')" -tenantid $TenantFilter | Select-Object $SelectList
        $Members = if ($Role.members) { $role.members | ForEach-Object { " $($_.displayName) ($($_.userPrincipalName))" } } else { 'none' }
        [PSCustomObject]@{
            DisplayName = $Role.displayName
            Description = $Role.description
            Members     = $Members -join ','
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $GraphRequest
        })

}
