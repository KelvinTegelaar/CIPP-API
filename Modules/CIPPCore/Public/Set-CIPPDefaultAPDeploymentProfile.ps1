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
        $GroupIds,
        $ExcludeGroupIds,
        [switch]$Reconcile,
        $HidePrivacy,
        $HideTerms,
        $AutoKeyboard,
        $Headers,
        $Language = 'os-default',
        $APIName = 'Add Default Autopilot Deployment Profile'
    )

    # Checked before the try so the clean message is thrown as-is rather than wrapped by the catch below.
    $NameCheck = Test-CIPPAutopilotProfileName -DisplayName $DisplayName
    if (-not $NameCheck.IsValid) {
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $NameCheck.Message -Sev 'Error'
        throw $NameCheck.Message
    }

    try {
        # Map language selection to Graph API locale values:
        # 'user-select' -> empty string (lets user choose during OOBE)
        # 'os-default' or $null -> $null (uses operating system default)
        # Specific tag (e.g. 'en-US') -> passed through as-is
        if ($Language -eq 'os-default') {
            $Language = $null
        }

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

        $IncludeGroupIds = @(if ($AssignTo -ne $true) { @($GroupIds) | Where-Object { $_ } })
        $ExcludeIds = @(@($ExcludeGroupIds) | Where-Object { $_ })
        if ($AssignTo -eq $true -or $IncludeGroupIds.Count -gt 0 -or $ExcludeIds.Count -gt 0 -or $Reconcile) {
            try {
                $AssignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($GraphRequest.id)/assignments"
                $ExistingAssignments = @(New-GraphGETRequest -uri $AssignmentsUri -tenantid $TenantFilter | Where-Object { $_ })
                $ExpectedTargets = [System.Collections.Generic.List[object]]::new()
                if ($AssignTo -eq $true) {
                    $ExpectedTargets.Add([ordered]@{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' })
                }
                foreach ($GroupId in $IncludeGroupIds) {
                    $ExpectedTargets.Add([ordered]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $GroupId })
                }
                foreach ($GroupId in $ExcludeIds) {
                    $ExpectedTargets.Add([ordered]@{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = $GroupId })
                }
                $TargetKey = { param($Target) "$($Target.'@odata.type')|$($Target.groupId)" }
                $ExistingKeys = @($ExistingAssignments | ForEach-Object { & $TargetKey $_.target })
                $ExpectedKeys = @($ExpectedTargets | ForEach-Object { & $TargetKey $_ })

                $Changes = [System.Collections.Generic.List[string]]::new()
                foreach ($Target in $ExpectedTargets) {
                    $Key = & $TargetKey $Target
                    if ($ExistingKeys -contains $Key) { continue }
                    $AssignBody = @{ target = $Target } | ConvertTo-Json -Depth 5 -Compress
                    if ($PSCmdlet.ShouldProcess($Key, "Assign Autopilot profile $DisplayName")) {
                        $null = New-GraphPOSTRequest -uri $AssignmentsUri -tenantid $TenantFilter -type POST -body $AssignBody
                        $Changes.Add("added $Key")
                    }
                }
                # Reconcile owns the profile's assignments: anything outside the expected set is removed.
                if ($Reconcile) {
                    foreach ($Assignment in $ExistingAssignments) {
                        $Key = & $TargetKey $Assignment.target
                        if ($ExpectedKeys -contains $Key) { continue }
                        if ($PSCmdlet.ShouldProcess($Key, "Remove Autopilot profile $DisplayName assignment")) {
                            $null = New-GraphPOSTRequest -uri "$AssignmentsUri/$($Assignment.id)" -tenantid $TenantFilter -type DELETE
                            $Changes.Add("removed $Key")
                        }
                    }
                }
                if ($Changes.Count -gt 0) {
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Updated assignments of autopilot profile $($DisplayName): $($Changes -join ', ')" -Sev 'Info'
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to assign Autopilot profile $($DisplayName): $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                # A plain all-devices assignment failure never failed the profile write; keep that for the manual page.
                if ($AssignTo -ne $true -or $Reconcile -or $ExcludeIds.Count -gt 0) { throw }
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
