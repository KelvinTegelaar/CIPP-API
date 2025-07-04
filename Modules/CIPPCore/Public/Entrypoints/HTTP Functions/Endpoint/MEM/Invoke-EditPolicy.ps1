using namespace System.Net

function Invoke-EditPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Note, suspect this is deprecated - rvdwegen
    # Note, I have a slight suspicion that might be the case too -Bobby

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Tenant = $Request.Body.tenantid
    $ID = $Request.Body.groupid
    $DisplayName = $Request.Body.Displayname
    $Description = $Request.Body.Description
    $AssignTo = if ($Request.Body.Assignto -ne 'on') { $Request.Body.Assignto }

    $Results = try {
        $CreateBody = '{"description":"' + $Description + '","displayName":"' + $DisplayName + '","roleScopeTagIds":["0"]}'
        $Request = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations('$ID')" -tenantid $Tenant -type PATCH -body $CreateBody
        Write-LogMessage -headers $Headers -API $APIName -tenant $($Tenant) -message "Edited policy $($DisplayName)" -Sev 'Info'
        if ($AssignTo) {
            $AssignBody = if ($AssignTo -ne 'AllDevicesAndUsers') { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations('$($ID)')/assign" -tenantid $Tenant -type POST -body $AssignBody
            Write-LogMessage -headers $Headers -API $APIName -tenant $($Tenant) -message "Assigned policy $($DisplayName) to $AssignTo" -Sev 'Info'
        }
        "Successfully edited policy for $($Tenant)"
    } catch {
        "Failed to add policy for $($Tenant): $($_.Exception.Message)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($Tenant) -message "Failed editing policy $($DisplayName). Error:$($_.Exception.Message)" -Sev 'Error'
        continue
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = $Results }
    }
}
