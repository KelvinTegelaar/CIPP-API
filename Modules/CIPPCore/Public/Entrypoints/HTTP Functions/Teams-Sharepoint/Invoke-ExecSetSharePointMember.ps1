using namespace System.Net

function Invoke-ExecSetSharePointMember {
    <#
    .SYNOPSIS
    Execute SharePoint member management for groups and sites
    
    .DESCRIPTION
    Adds or removes members from SharePoint groups and sites using Microsoft Graph API with support for different SharePoint types
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
        
    .NOTES
    Group: Teams & SharePoint
    Summary: Exec Set SharePoint Member
    Description: Adds or removes members from SharePoint groups and sites using Microsoft Graph API with support for different SharePoint types including group-based sites
    Tags: SharePoint,Members,Groups,Graph API
    Parameter: tenantFilter (string) [body] - Target tenant identifier
    Parameter: SharePointType (string) [body] - Type of SharePoint site: Group
    Parameter: GroupID (string) [body] - Group email address or identifier
    Parameter: user.value (string) [body] - User identifier to add or remove
    Parameter: Add (boolean) [body] - Whether to add (true) or remove (false) the user
    Response: Returns an object with the following properties:
    Response: - Results (string): Success or error message
    Response: On success: Success message with HTTP 200 status
    Response: On unsupported type: Error message with HTTP 400 status
    Response: On error: Exception message with HTTP 500 status
    Example: {
      "Results": "Successfully added user@contoso.com to SharePoint group"
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter

    try {
        if ($Request.Body.SharePointType -eq 'Group') {
            $GroupId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=mail eq '$($Request.Body.GroupID)' or proxyAddresses/any(x:endsWith(x,'$($Request.Body.GroupID)'))&`$count=true" -ComplexFilter -tenantid $TenantFilter).id
            if ($Request.Body.Add -eq $true) {
                $Results = Add-CIPPGroupMember -GroupType 'Team' -GroupID $GroupID -Member $Request.Body.user.value -TenantFilter $TenantFilter -Headers $Headers
            }
            else {
                $UserID = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($Request.Body.user.value)" -tenantid $TenantFilter).id
                $Results = Remove-CIPPGroupMember -GroupType 'Team' -GroupID $GroupID -Member $UserID -TenantFilter $TenantFilter -Headers $Headers
            }
        }
        else {
            $StatusCode = [HttpStatusCode]::BadRequest
            $Results = 'This type of SharePoint site is not supported.'
        }
    }
    catch {
        $Results = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })

}
