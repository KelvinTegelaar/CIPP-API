function Set-CIPPDefaultAPDeploymentProfile {
    [CmdletBinding()]
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
        $assignTo,
        $hidePrivacy,
        $hideTerms,
        $Autokeyboard,
        $ExecutingUser,
        $APIName = 'Add Default Enrollment Status Page'
    )
    try {
        $ObjBody = [pscustomobject]@{
            '@odata.type'                            = '#microsoft.graph.azureADWindowsAutopilotDeploymentProfile'
            'displayName'                            = "$($displayname)"
            'description'                            = "$($description)"
            'deviceNameTemplate'                     = "$($DeviceNameTemplate)"
            'language'                               = 'os-default'
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
        Write-Host $Body
        $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles' -body $body -tenantid $tenantfilter
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $($tenantfilter) -message "Added Autopilot profile $($Displayname)" -Sev 'Info'
        if ($AssignTo) {
            $AssignBody = '{"target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}}'
            $assign = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($GraphRequest.id)/assignments" -tenantid $tenantfilter -type POST -body $AssignBody
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $($tenantfilter) -message "Assigned autopilot profile $($Displayname) to $AssignTo" -Sev 'Info'
        }
        "Successfully added profile for $($tenantfilter)"
    } catch {
        "Failed to add profile for $($tenantfilter): $($_.Exception.Message)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $($tenantfilter) -message "Failed adding Autopilot Profile $($Displayname). Error: $($_.Exception.Message)" -Sev 'Error'
        continue
    }
}
