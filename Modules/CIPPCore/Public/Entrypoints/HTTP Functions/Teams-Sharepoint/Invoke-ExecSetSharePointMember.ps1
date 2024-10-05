using namespace System.Net

Function Invoke-ExecSetSharePointMember {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    if ($Request.body.SharePointType -eq 'Group') {
        $GroupId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=mail eq '$($Request.Body.GroupID)'" -tenantid $Request.Body.TenantFilter).id
        if ($Request.body.Add -eq $true) {
            $Results = Add-CIPPGroupMember -GroupType 'Team' -GroupID $GroupID -Member $Request.Body.input -TenantFilter $Request.Body.TenantFilter -ExecutingUser $request.headers.'x-ms-client-principal'
        } else {
            $UserID = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($Request.Body.input)" -tenantid $Request.Body.TenantFilter).id
            $Results = Remove-CIPPGroupMember -GroupType 'Team' -GroupID $GroupID -Member $UserID -TenantFilter $Request.Body.TenantFilter -ExecutingUser $request.headers.'x-ms-client-principal'
        }
    } else {
        $Results = 'This type of SharePoint site is not supported.'
    }
    $body = [pscustomobject]@{'Results' = $Results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
