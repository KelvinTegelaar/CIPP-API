using namespace System.Net

Function Invoke-ExecAssignPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Tenant = $request.body.tenantfilter
    $ID = $request.body.id
    $displayname = $request.body.Displayname
    $AssignTo = if ($request.body.Assignto -ne 'on') { $request.body.Assignto }

    $results = try {
        if ($AssignTo) {
            $assign = Set-CIPPAssignedPolicy -PolicyId $ID -TenantFilter $tenant -GroupName $AssignTo -Type $Request.body.Type
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Assigned policy $($Displayname) to $AssignTo" -Sev 'Info'
        }
        "Successfully edited policy for $($Tenant)"
    } catch {
        "Failed to add policy for $($Tenant): $($_.Exception.Message)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed editing policy $($Displayname). Error:$($_.Exception.Message)" -Sev 'Error'
        continue
    }

    $body = [pscustomobject]@{'Results' = $results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
