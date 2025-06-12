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


    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $Request.body.tenantFilter



    if ($Request.body.SharePointType -eq 'Group') {
        $GroupId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=mail eq '$($Request.Body.GroupID)' or proxyAddresses/any(x:endsWith(x,'$($Request.Body.GroupID)'))&`$count=true" -ComplexFilter -tenantid $TenantFilter).id
        if ($Request.body.Add -eq $true) {
            $Results = Add-CIPPGroupMember -GroupType 'Team' -GroupID $GroupID -Member $Request.Body.user.value -TenantFilter $TenantFilter -Headers $Request.Headers
        } else {
            $UserID = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($Request.Body.user.value)" -tenantid $TenantFilter).id
            $Results = Remove-CIPPGroupMember -GroupType 'Team' -GroupID $GroupID -Member $UserID -TenantFilter $TenantFilter -Headers $Request.Headers
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
