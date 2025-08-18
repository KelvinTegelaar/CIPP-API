using namespace System.Net

function Invoke-ExecSetSharePointMember {
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
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter

    try {
        if ($Request.Body.SharePointType -eq 'Group') {
            if ($Request.Body.GroupID -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
                $GroupId = $Request.Body.GroupID
            } else {
                $GroupId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=mail eq '$($Request.Body.GroupID)' or proxyAddresses/any(x:endsWith(x,'$($Request.Body.GroupID)')) or mailNickname eq '$($Request.Body.GroupID)'" -ComplexFilter -tenantid $TenantFilter).id
            }
            
            if ($Request.Body.Add -eq $true) {
                $Results = Add-CIPPGroupMember -GroupType 'Team' -GroupID $GroupID -Member $Request.Body.user.value -TenantFilter $TenantFilter -Headers $Headers
            } else {
                $UserID = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($Request.Body.user.value)" -tenantid $TenantFilter).id
                $Results = Remove-CIPPGroupMember -GroupType 'Team' -GroupID $GroupID -Member $UserID -TenantFilter $TenantFilter -Headers $Headers
            }
            $StatusCode = [HttpStatusCode]::OK
        } else {
            $StatusCode = [HttpStatusCode]::BadRequest
            $Results = 'This type of SharePoint site is not supported.'
        }
    } catch {
        $Results = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })

}
