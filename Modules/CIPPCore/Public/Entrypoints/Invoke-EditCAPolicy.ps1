using namespace System.Net

Function Invoke-EditCAPolicy {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Tenant = $request.query.tenantFilter
    $ID = $request.query.guid
    $results = try {
        $EditBody = "{`"state`": `"$($request.query.state)`"}"
        $Request = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta//identity/conditionalAccess/policies/$($id)" -tenantid $tenant -type PATCH -body $EditBody
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Edited CA policy $($ID)" -Sev 'Error'
        'Successfully edited CA policy'
    } catch {
        "Failed to add CA policy: $($_.Exception.Message)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed editing CA policy $($ID). Error: $($_.Exception.Message)" -Sev 'Error'
        continue
    }

    $body = [pscustomobject]@{'Results' = $results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
