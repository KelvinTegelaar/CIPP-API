using namespace System.Net

Function Invoke-ExecAssignPolicy {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Tenant = $request.query.tenantfilter
    $ID = $request.query.id
    $displayname = $request.query.Displayname
    $AssignTo = if ($request.query.Assignto -ne 'on') { $request.query.Assignto }
    
    $results = try {
        if ($AssignTo) {
            $assign = Set-CIPPAssignedPolicy -PolicyId $ID -TenantFilter $tenant -GroupName $AssignTo -Type $Request.query.Type
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
