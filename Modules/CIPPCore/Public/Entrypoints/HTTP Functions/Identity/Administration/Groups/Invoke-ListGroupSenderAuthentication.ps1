using namespace System.Net

Function Invoke-ListGroupSenderAuthentication {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.

    $TenantFilter = $Request.Query.TenantFilter
    $groupid = $Request.query.groupid

    $params = @{
        Identity = $groupid
    }

    Write-Host = "This is the group id $groupid"
    Write-Host = "This is the tenant filter $TenantFilter"
    $GroupType = Invoke-ListGroups -tenantFilter $TenantFilter -GroupID $groupid
    Write-Host = "This is the group type $($GroupType.calculatedGroupType)"

    try {
        $Request = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DistributionGroup' -cmdParams $params -UseSystemMailbox $true
        $StatusCode = [HttpStatusCode]::OK 
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Request = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ enabled = $Request.RequireSenderAuthenticationEnabled }
        })
}