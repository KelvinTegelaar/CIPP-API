function Set-CIPPDefaultAPDeploymentProfile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $TenantFilter,
        $DisplayName,
        $Description,
        $DeviceNameTemplate,
        $AllowWhiteGlove,
        $CollectHash,
        $UserType,
        $DeploymentMode,
        $HideChangeAccount = $true,
        $AssignTo,
        $HidePrivacy,
        $HideTerms,
        $AutoKeyboard,
        $Headers,
        $Language = 'os-default',
        $APIName = 'Add Default Autopilot Deployment Profile'
    )

    try {
        if ($Language -in @('user-select', 'os-default')) { $Language = '' }

        # userType in outOfBoxExperienceSetting is only valid for user-driven (singleUser) mode.
        # The Intune API rejects it for self-deploying (shared) mode.
        $OutOfBoxSetting = [ordered]@{
            'deviceUsageType'              = "$DeploymentMode"
            'escapeLinkHidden'             = $([bool]($true))
            'privacySettingsHidden'        = $([bool]($HidePrivacy))
            'eulaHidden'                   = $([bool]($HideTerms))
            'keyboardSelectionPageSkipped' = $([bool]($AutoKeyboard))
        }
        if ($DeploymentMode -ne 'shared') {
            $OutOfBoxSetting['userType'] = "$UserType"
        }

        $ObjBody = [pscustomobject]@{
            '@odata.type'                   = '#microsoft.graph.azureADWindowsAutopilotDeploymentProfile'
            'displayName'                   = "$($DisplayName)"
            'description'                   = "$($Description)"
            'deviceNameTemplate'            = "$($DeviceNameTemplate)"
            'locale'                        = "$($Language)"
            'preprovisioningAllowed'        = $([bool]($AllowWhiteGlove))
            'deviceType'                    = 'windowsPc'
            'hardwareHashExtractionEnabled' = $([bool]($CollectHash))
            'roleScopeTagIds'               = @()
            'outOfBoxExperienceSetting'     = $OutOfBoxSetting
        }
        $Body = ConvertTo-Json -InputObject $ObjBody -Depth 10

        Write-Information $Body

        $Profiles = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles' -tenantid $TenantFilter | Where-Object -Property displayName -EQ $DisplayName
        if ($Profiles.count -gt 1) {
            $Profiles | ForEach-Object {
                if ($_.id -ne $Profiles[0].id) {
                    if ($PSCmdlet.ShouldProcess($_.displayName, 'Delete duplicate Autopilot profile')) {
                        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($_.id)" -tenantid $TenantFilter -type DELETE
                        Write-LogMessage -Headers $Headers -API $APIName -tenant $($TenantFilter) -message "Deleted duplicate Autopilot profile $($DisplayName)" -Sev 'Info'
                    }
                }
            }
            $Profiles = $Profiles[0]
        }
        if (!$Profiles) {
            if ($PSCmdlet.ShouldProcess($DisplayName, 'Add Autopilot profile')) {
                $Type = 'Add'
                $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles' -body $Body -tenantid $TenantFilter
                Write-LogMessage -Headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added Autopilot profile $($DisplayName)" -Sev 'Info'
            }
        } else {
            $Type = 'Edit'
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($Profiles.id)" -tenantid $TenantFilter -body $Body -type PATCH
            $GraphRequest = $Profiles | Select-Object -Last 1
        }

        if ($AssignTo -eq $true) {
            try {
                $AssignBody = '{"target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}}'
                if ($PSCmdlet.ShouldProcess($AssignTo, "Assign Autopilot profile $DisplayName")) {
                    #Get assignments
                    $Assignments = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($GraphRequest.id)/assignments" -tenantid $TenantFilter
                    if (!$Assignments) {
                        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($GraphRequest.id)/assignments" -tenantid $TenantFilter -type POST -body $AssignBody
                    }
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Assigned autopilot profile $($DisplayName) to $($AssignTo)" -Sev 'Info'
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to assign Autopilot profile $($DisplayName) to $($AssignTo): $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            }
        }
        "Successfully $($Type)ed profile for $($TenantFilter)"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed $($Type)ing Autopilot Profile $($DisplayName). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}
