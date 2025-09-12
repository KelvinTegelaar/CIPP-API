function Remove-CIPPAutopilotProfile {
    param(
        $ProfileId,
        $DisplayName,
        $TenantFilter,
        $Assignments,
        $Headers,
        $APIName = 'Remove Autopilot Profile'
    )


    try {

        try {
            $DisplayName = $null -eq $DisplayName ? $ProfileId : $DisplayName
            if ($Assignments.Count -gt 0) {
                Write-Host "Profile $ProfileId has $($Assignments.Count) assignments, removing them first"
                throw
            }

            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$ProfileId" -tenantid $TenantFilter -type DELETE
            $Result = "Successfully deleted Autopilot profile '$($DisplayName)'"
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
            return $Result
        } catch {

            # Profile could not be deleted, there is probably an assignment still referencing it. The error is bloody useless here, and we just need to try some stuff
            if ($null -eq $Assignments) {
                $Assignments = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$ProfileId/assignments" -tenantid $TenantFilter
            }

            # Remove all assignments
            if ($Assignments -and $Assignments.Count -gt 0) {
                foreach ($Assignment in $Assignments) {
                    try {
                        # Use the assignment ID directly as provided by the API
                        $AssignmentId = $Assignment.id
                        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$ProfileId/assignments/$AssignmentId" -tenantid $TenantFilter -type DELETE

                    } catch {
                        # Handle the case where the assignment might reference a deleted group
                        try {
                            if ($Assignment.target -and $Assignment.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget') {
                                $GroupId = $Assignment.target.groupId
                                $AlternativeAssignmentId = "${ProfileId}_${GroupId}"
                                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$ProfileId/assignments/$AlternativeAssignmentId" -tenantid $TenantFilter -type DELETE
                            }
                        } catch {
                            throw "Could not remove assignment $AssignmentId"
                        }
                    }
                }
            }
            # Retry deleting the profile after removing assignments
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$ProfileId" -tenantid $TenantFilter -type DELETE
            $Result = "Successfully deleted Autopilot profile '$($DisplayName)' "
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
            return $Result
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $ErrorText = "Failed to delete Autopilot profile $ProfileId. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $ErrorText -Sev 'Error' -LogData $ErrorMessage
        throw $ErrorText
    }
}
