using namespace System.Net

Function Invoke-EditPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Tenant = $request.body.tenantid
    $ID = $request.body.groupid
    $displayname = $request.body.Displayname
    $description = $request.body.Description
    $AssignTo = if ($request.body.Assignto -ne 'on') { $request.body.Assignto }

    $results = try {
        $CreateBody = '{"description":"' + $description + '","displayName":"' + $displayname + '","roleScopeTagIds":["0"]}'
        $Request = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations('$ID')" -tenantid $tenant -type PATCH -body $CreateBody
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($Tenant) -message "Edited policy $($Displayname)" -Sev 'Info'
        if ($AssignTo) {
            $AssignBody = if ($AssignTo -ne 'AllDevicesAndUsers') { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
            $assign = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations('$($ID)')/assign" -tenantid $tenant -type POST -body $AssignBody
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($Tenant) -message "Assigned policy $($Displayname) to $AssignTo" -Sev 'Info'
        }
        "Successfully edited policy for $($Tenant)"
    }
    catch {
        "Failed to add policy for $($Tenant): $($_.Exception.Message)"
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($Tenant) -message "Failed editing policy $($Displayname). Error:$($_.Exception.Message)" -Sev 'Error'
        continue
    }

    $body = [pscustomobject]@{'Results' = $results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
