function Invoke-ExecAssignAutopilotProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $ProfileId = $Request.Body.ProfileId
    $ProfileName = $Request.Body.ProfileName
    $AssignTo = $Request.Body.AssignTo

    try {
        if ([string]::IsNullOrEmpty($TenantFilter)) { throw 'Tenant filter is required' }
        if ([string]::IsNullOrEmpty($ProfileId)) { throw 'Profile ID is required' }
        if ([string]::IsNullOrEmpty($AssignTo)) { throw 'AssignTo is required' }

        $BaseUri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$ProfileId/assignments"
        $Existing = @(New-GraphGETRequest -uri $BaseUri -tenantid $TenantFilter)

        if ($AssignTo -eq 'AllDevices') {
            $AlreadyAssigned = $Existing | Where-Object { $_.target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget' }
            if ($AlreadyAssigned) {
                $Result = "Profile $ProfileName is already assigned to all devices"
            } else {
                $Body = '{"target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}}'
                $null = New-GraphPOSTRequest -uri $BaseUri -tenantid $TenantFilter -type POST -body $Body
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Assigned autopilot profile $ProfileName to all devices" -Sev 'Info'
                $Result = "Successfully assigned profile $ProfileName to all devices"
            }
        } elseif ($AssignTo -eq 'RemoveAll') {
            if ($Existing.Count -eq 0) {
                $Result = "Profile $ProfileName has no assignments to remove"
            } else {
                $Removed = 0
                foreach ($Assignment in $Existing) {
                    $null = New-GraphPOSTRequest -uri "$BaseUri/$($Assignment.id)" -tenantid $TenantFilter -type DELETE
                    $Removed++
                }
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Removed all $Removed assignment(s) from autopilot profile $ProfileName" -Sev 'Info'
                $Result = "Successfully removed all $Removed assignment(s) from profile $ProfileName"
            }
        } elseif ($AssignTo -eq 'RemoveGroups') {
            $GroupIds = @(
                $Request.Body.GroupIds | ForEach-Object {
                    if ($_ -is [string]) { $_.Trim() } elseif ($_ -and $_.value) { $_.value }
                } | Where-Object { $_ }
            )
            if ($GroupIds.Count -eq 0) { throw 'At least one assignment is required' }

            $Removed = 0
            foreach ($Assignment in $Existing) {
                $TargetId = if ($Assignment.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget') {
                    $Assignment.target.groupId
                } elseif ($Assignment.target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget') {
                    'allDevices'
                }
                if ($TargetId -and $GroupIds -contains $TargetId) {
                    $null = New-GraphPOSTRequest -uri "$BaseUri/$($Assignment.id)" -tenantid $TenantFilter -type DELETE
                    $Removed++
                }
            }
            if ($Removed -gt 0) {
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Removed $Removed assignment(s) from autopilot profile $ProfileName" -Sev 'Info'
                $Result = "Successfully removed $Removed assignment(s) from profile $ProfileName"
            } else {
                $Result = "No matching assignments found to remove from profile $ProfileName"
            }
        } else {
            # Accept both bare strings and { value, label } option objects
            $GroupIds = @(
                $Request.Body.GroupIds | ForEach-Object {
                    if ($_ -is [string]) { $_.Trim() } elseif ($_ -and $_.value) { $_.value }
                } | Where-Object { $_ }
            )
            if ($GroupIds.Count -eq 0) { throw 'At least one group ID is required' }

            $ExistingGroupIds = @($Existing |
                    Where-Object { $_.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget' } |
                    ForEach-Object { $_.target.groupId })

            $Created = [System.Collections.Generic.List[string]]::new()
            foreach ($GroupId in $GroupIds) {
                if ($ExistingGroupIds -contains $GroupId) { continue }
                $Body = @{
                    target = @{
                        '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                        groupId       = $GroupId
                    }
                } | ConvertTo-Json -Depth 5 -Compress
                $null = New-GraphPOSTRequest -uri $BaseUri -tenantid $TenantFilter -type POST -body $Body
                $Created.Add($GroupId)
            }

            if ($Created.Count -gt 0) {
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Assigned autopilot profile $ProfileName to group(s): $($Created -join ', ')" -Sev 'Info'
                $Result = "Successfully assigned profile $ProfileName to $($Created.Count) group(s)"
            } else {
                $Result = "Profile $ProfileName is already assigned to all specified groups"
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to assign autopilot profile $ProfileName`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Result = "Failed to assign profile: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })
}
