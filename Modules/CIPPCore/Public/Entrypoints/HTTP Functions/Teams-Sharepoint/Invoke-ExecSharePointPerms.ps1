using namespace System.Net

function Invoke-ExecSharePointPerms {
    <#
    .SYNOPSIS
    Execute SharePoint permissions management for OneDrive and sites
    
    .DESCRIPTION
    Manages SharePoint permissions for OneDrive accounts and SharePoint sites including adding and removing user access
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
        
    .NOTES
    Group: Teams & SharePoint
    Summary: Exec SharePoint Perms
    Description: Manages SharePoint permissions for OneDrive accounts and SharePoint sites including adding and removing user access through SharePoint Online PowerShell
    Tags: SharePoint,OneDrive,Permissions,Administration
    Parameter: tenantFilter (string) [body] - Target tenant identifier
    Parameter: UPN (string) [body] - User Principal Name or ID of the OneDrive account to modify
    Parameter: onedriveAccessUser (object) [body] - User object with value property for the user to add/remove permissions for
    Parameter: user (object) [body] - Alternative user object with value property
    Parameter: URL (string) [body] - SharePoint site URL for site-level permissions
    Parameter: RemovePermission (boolean) [body] - Whether to remove permissions (true) or add permissions (false)
    Response: Returns an object with the following properties:
    Response: - Results (string): Success or error message
    Response: On success: Success message with HTTP 200 status
    Response: On error: Error message with HTTP 400 status
    Example: {
      "Results": "Successfully added permissions for user@contoso.com to OneDrive account"
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev Debug

    $TenantFilter = $Request.Body.tenantFilter

    Write-Host '===================================='
    Write-Host 'Request Body:'
    Write-Host (ConvertTo-Json $Request.body -Depth 10)
    Write-Host '===================================='


    # The UPN or ID of the users OneDrive we are changing permissions on
    $UserId = $Request.Body.UPN
    # The UPN of the user we are adding or removing permissions for
    $OnedriveAccessUser = $Request.Body.onedriveAccessUser.value ?? $Request.Body.user.value
    $URL = $Request.Body.URL
    $RemovePermission = $Request.Body.RemovePermission

    try {

        $State = Set-CIPPSharePointPerms -tenantFilter $TenantFilter `
            -UserId $UserId `
            -OnedriveAccessUser $OnedriveAccessUser `
            -Headers $Headers `
            -APIName $APIName `
            -RemovePermission $RemovePermission `
            -URL $URL
        $Result = "$State"
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $Result = "Failed. Error: $ErrorMessage"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
