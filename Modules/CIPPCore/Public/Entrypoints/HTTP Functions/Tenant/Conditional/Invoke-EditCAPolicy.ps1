using namespace System.Net

Function Invoke-EditCAPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Tenant = $request.query.tenantFilter
    $ID = $request.query.guid
    $results = try {
        $EditBody = "{`"state`": `"$($request.query.state)`"}"
        $Request = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta//identity/conditionalAccess/policies/$($id)" -tenantid $tenant -type PATCH -body $EditBody -asapp $true
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Edited CA policy: $($ID)" -Sev 'Info'
        "Successfully edited CA policy: $($ID)"
    } catch {
        "Failed to add CA policy: $($_.Exception.Message)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed editing CA policy $($ID). Error: $($_.Exception.Message)" -Sev 'Error'
    }

    $body = [pscustomobject]@{'Results' = $results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
