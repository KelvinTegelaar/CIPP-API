function Set-CIPPDefaultAPDeploymentProfile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $tenantFilter,
        $displayname,
        $description,
        $devicenameTemplate,
        $allowWhiteGlove,
        $CollectHash,
        $usertype,
        $DeploymentMode,
        $hideChangeAccount,
        $AssignTo,
        $hidePrivacy,
        $hideTerms,
        $Autokeyboard,
        $ExecutingUser,
        $Language = 'os-default',
        $APIName = 'Add Default Enrollment Status Page'
    )
    try {
        $ObjBody = [pscustomobject]@{
            '@odata.type'                            = '#microsoft.graph.azureADWindowsAutopilotDeploymentProfile'
            'displayName'                            = "$($displayname)"
            'description'                            = "$($description)"
            'deviceNameTemplate'                     = "$($DeviceNameTemplate)"
            'language'                               = "$($Language)"
            'enableWhiteGlove'                       = $([bool]($allowWhiteGlove))
            'deviceType'                             = 'windowsPc'
            'extractHardwareHash'                    = $([bool]($CollectHash))
            'roleScopeTagIds'                        = @()
            'hybridAzureADJoinSkipConnectivityCheck' = $false
            'outOfBoxExperienceSettings'             = @{
                'deviceUsageType'           = "$DeploymentMode"
                'hideEscapeLink'            = $([bool]($hideChangeAccount))
                'hidePrivacySettings'       = $([bool]($hidePrivacy))
                'hideEULA'                  = $([bool]($hideTerms))
                'userType'                  = "$usertype"
                'skipKeyboardSelectionPage' = $([bool]($Autokeyboard))
            }
        }
        $Body = ConvertTo-Json -InputObject $ObjBody

        $Profiles = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles' -tenantid $tenantfilter | Where-Object -Property displayName -EQ $displayname
        if ($Profiles.count -gt 1) {
            $Profiles | ForEach-Object {
                if ($_.id -ne $Profiles[0].id) {
                    if ($PSCmdlet.ShouldProcess($_.displayName, 'Delete duplicate Autopilot profile')) {
                        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($_.id)" -tenantid $tenantfilter -type DELETE
                        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $($tenantfilter) -message "Deleted duplicate Autopilot profile $($displayname)" -Sev 'Info'
                    }
                }
            }
            $Profiles = $Profiles[0]
        }
        if (!$Profiles) {
            if ($PSCmdlet.ShouldProcess($displayName, 'Add Autopilot profile')) {
                $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles' -body $body -tenantid $tenantfilter
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $($tenantfilter) -message "Added Autopilot profile $($displayname)" -Sev 'Info'
            }
        } else {
            $GraphRequest = $Profiles
        }

        if ($AssignTo -eq $true) {
            $AssignBody = '{"target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}}'
            if ($PSCmdlet.ShouldProcess($AssignTo, "Assign Autopilot profile $displayname")) {
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($GraphRequest.id)/assignments" -tenantid $tenantfilter -type POST -body $AssignBody
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $($tenantfilter) -message "Assigned autopilot profile $($Displayname) to $AssignTo" -Sev 'Info'
            }
        }
        "Successfully added profile for $($tenantfilter)"
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $($tenantfilter) -message "Failed adding Autopilot Profile $($Displayname). Error: $($_.Exception.Message)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
        throw "Failed to add profile for $($tenantfilter): $($_.Exception.Message)"
    }
}
