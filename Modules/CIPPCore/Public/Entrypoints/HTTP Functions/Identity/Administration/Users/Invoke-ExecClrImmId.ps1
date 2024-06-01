using namespace System.Net

Function Invoke-ExecClrImmId {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    Try {
        $TenantFilter = $Request.Query.TenantFilter
        $UserID = $Request.Query.ID
        $Body = [pscustomobject] @{
            onPremisesImmutableId = $null
        } | ConvertTo-Json
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$UserID" -tenantid $TenantFilter -type PATCH -body $Body
        $Results = [pscustomobject]@{'Results' = 'Successfully Cleared ImmutableId' }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed. $_.Exception.Message"; colour = 'danger' }
        $_.Exception
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
