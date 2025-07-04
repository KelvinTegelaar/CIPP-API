function Set-CIPPDefaultAPDeploymentProfile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $TenantFilter,
        $displayName,
        $description,
        $devicenameTemplate,
        $allowWhiteGlove,
        $CollectHash,
        $userType,
        $DeploymentMode,
        $hideChangeAccount,
        $AssignTo,
        $hidePrivacy,
        $hideTerms,
        $AutoKeyboard,
        $Headers,
        $Language = 'os-default',
        $APIName = 'Add Default Enrollment Status Page'
    )


    try {
        $ObjBody = [pscustomobject]@{
            '@odata.type'                            = '#microsoft.graph.azureADWindowsAutopilotDeploymentProfile'
            'displayName'                            = "$($displayName)"
            'description'                            = "$($description)"
            'deviceNameTemplate'                     = "$($devicenameTemplate)"
            'language'                               = "$($Language)"
            'enableWhiteGlove'                       = $([bool]($allowWhiteGlove))
            'deviceType'                             = 'windowsPc'
            'extractHardwareHash'                    = $([bool]($CollectHash))
            'roleScopeTagIds'                        = @()
            'hybridAzureADJoinSkipConnectivityCheck' = $false
            'outOfBoxExperienceSetting'              = @{
                'deviceUsageType'              = "$DeploymentMode"
                'escapeLinkHidden'             = $([bool]($hideChangeAccount))
                'privacySettingsHidden'        = $([bool]($hidePrivacy))
                'eulaHidden'                   = $([bool]($hideTerms))
                'userType'                     = "$userType"
                'keyboardSelectionPageSkipped' = $([bool]($AutoKeyboard))
            }
        }
        $Body = ConvertTo-Json -InputObject $ObjBody

        $Profiles = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles' -tenantid $TenantFilter | Where-Object -Property displayName -EQ $displayName
        if ($Profiles.count -gt 1) {
            $Profiles | ForEach-Object {
                if ($_.id -ne $Profiles[0].id) {
                    if ($PSCmdlet.ShouldProcess($_.displayName, 'Delete duplicate Autopilot profile')) {
                        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($_.id)" -tenantid $TenantFilter -type DELETE
                        Write-LogMessage -Headers $Headers -API $APIName -tenant $($TenantFilter) -message "Deleted duplicate Autopilot profile $($displayName)" -Sev 'Info'
                    }
                }
            }
            $Profiles = $Profiles[0]
        }
        if (!$Profiles) {
            if ($PSCmdlet.ShouldProcess($displayName, 'Add Autopilot profile')) {
                $Type = 'Add'
                $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles' -body $body -tenantid $TenantFilter
                Write-LogMessage -Headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added Autopilot profile $($displayName)" -Sev 'Info'
            }
        } else {
            $Type = 'Edit'
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($Profiles.id)" -tenantid $TenantFilter -body $body -type PATCH
            $GraphRequest = $Profiles | Select-Object -Last 1
        }

        if ($AssignTo -eq $true) {
            $AssignBody = '{"target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}}'
            if ($PSCmdlet.ShouldProcess($AssignTo, "Assign Autopilot profile $displayName")) {
                #Get assignments
                $Assignments = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($GraphRequest.id)/assignments" -tenantid $TenantFilter
                if (!$Assignments) {
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($GraphRequest.id)/assignments" -tenantid $TenantFilter -type POST -body $AssignBody
                }
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Assigned autopilot profile $($displayName) to $AssignTo" -Sev 'Info'
            }
        }
        "Successfully $($Type)ed profile for $TenantFilter"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APIName -tenant $tenantFilter -message "Failed $($Type)ing Autopilot Profile $($displayName). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw "Failed to add profile for $($tenantFilter): $($ErrorMessage.NormalizedError)"
    }
}
