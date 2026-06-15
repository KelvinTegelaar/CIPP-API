function Invoke-CIPPStandardAutopatchGroup {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AutopatchGroup
    .SYNOPSIS
        (Label) Deploy Windows Autopatch Group
    .DESCRIPTION
        (Helptext) Deploys a Windows Autopatch group with configurable deployment ring settings for quality updates, feature updates, Edge, and Office.
        (DocsDescription) Creates or updates a Windows Autopatch deployment group with Test and Last deployment rings. Configures quality update deferrals, feature update targeting, Edge and Office update channels per ring. Uses the Autopatch API proxy to manage the group configuration.
    .NOTES
        CAT
            Intune Standards
        TAG
        EXECUTIVETEXT
            Configures Windows Autopatch deployment groups to manage update delivery across devices. Autopatch automates Windows quality updates, feature updates, Edge, and Office updates using deployment rings with configurable deferrals and deadlines.
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.AutopatchGroup.GroupName","label":"Group Name","required":true,"defaultValue":"Autopatch default group"}
            {"type":"select","multiple":false,"name":"standards.AutopatchGroup.TargetOSVersion","label":"Target OS Version","required":true,"options":[{"label":"Windows 11, version 24H2","value":"Windows 11, version 24H2"},{"label":"Windows 11, version 25H2","value":"Windows 11, version 25H2"}],"defaultValue":"Windows 11, version 25H2"}
            {"type":"switch","name":"standards.AutopatchGroup.EnableDriverUpdate","label":"Enable Driver Updates","defaultValue":true}
            {"type":"switch","name":"standards.AutopatchGroup.InstallWin10OnWin11Ineligible","label":"Install latest Windows 10 on Windows 11 ineligible devices","defaultValue":false}
            {"type":"number","name":"standards.AutopatchGroup.TestQualityDeferral","label":"Test Ring - Quality Update Deferral (days)","defaultValue":0,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":30,"message":"Maximum value is 30"}}}
            {"type":"number","name":"standards.AutopatchGroup.TestQualityDeadline","label":"Test Ring - Quality Update Deadline (days)","defaultValue":1,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":30,"message":"Maximum value is 30"}}}
            {"type":"number","name":"standards.AutopatchGroup.TestQualityGracePeriod","label":"Test Ring - Quality Update Grace Period (days)","defaultValue":1,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":7,"message":"Maximum value is 7"}}}
            {"type":"number","name":"standards.AutopatchGroup.TestFeatureDeferral","label":"Test Ring - Feature Update Deferral (days)","defaultValue":0,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":365,"message":"Maximum value is 365"}}}
            {"type":"number","name":"standards.AutopatchGroup.TestFeatureDeadline","label":"Test Ring - Feature Update Deadline (days)","defaultValue":5,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":30,"message":"Maximum value is 30"}}}
            {"type":"select","multiple":false,"name":"standards.AutopatchGroup.TestEdgeChannel","label":"Test Ring - Edge Update Channel","options":[{"label":"Stable","value":"Stable"},{"label":"Beta","value":"Beta"},{"label":"Dev","value":"Dev"}],"defaultValue":"Beta"}
            {"type":"select","multiple":false,"name":"standards.AutopatchGroup.TestOfficeChannel","label":"Test Ring - Office Update Channel","options":[{"label":"Current","value":"Current"},{"label":"Monthly Enterprise","value":"MonthlyEnterprise"},{"label":"Semi-Annual Enterprise","value":"SemiAnnual"}],"defaultValue":"MonthlyEnterprise"}
            {"type":"number","name":"standards.AutopatchGroup.LastQualityDeferral","label":"Last Ring - Quality Update Deferral (days)","defaultValue":1,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":30,"message":"Maximum value is 30"}}}
            {"type":"number","name":"standards.AutopatchGroup.LastQualityDeadline","label":"Last Ring - Quality Update Deadline (days)","defaultValue":2,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":30,"message":"Maximum value is 30"}}}
            {"type":"number","name":"standards.AutopatchGroup.LastQualityGracePeriod","label":"Last Ring - Quality Update Grace Period (days)","defaultValue":2,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":7,"message":"Maximum value is 7"}}}
            {"type":"number","name":"standards.AutopatchGroup.LastFeatureDeferral","label":"Last Ring - Feature Update Deferral (days)","defaultValue":0,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":365,"message":"Maximum value is 365"}}}
            {"type":"number","name":"standards.AutopatchGroup.LastFeatureDeadline","label":"Last Ring - Feature Update Deadline (days)","defaultValue":5,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":30,"message":"Maximum value is 30"}}}
            {"type":"select","multiple":false,"name":"standards.AutopatchGroup.LastEdgeChannel","label":"Last Ring - Edge Update Channel","options":[{"label":"Stable","value":"Stable"},{"label":"Beta","value":"Beta"},{"label":"Dev","value":"Dev"}],"defaultValue":"Stable"}
            {"type":"select","multiple":false,"name":"standards.AutopatchGroup.LastOfficeChannel","label":"Last Ring - Office Update Channel","options":[{"label":"Current","value":"Current"},{"label":"Monthly Enterprise","value":"MonthlyEnterprise"},{"label":"Semi-Annual Enterprise","value":"SemiAnnual"}],"defaultValue":"MonthlyEnterprise"}
            {"type":"number","name":"standards.AutopatchGroup.LastOfficeDeferral","label":"Last Ring - Office Update Deferral (days)","defaultValue":1,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":30,"message":"Maximum value is 30"}}}
            {"type":"number","name":"standards.AutopatchGroup.LastOfficeDeadline","label":"Last Ring - Office Update Deadline (days)","defaultValue":2,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":30,"message":"Maximum value is 30"}}}
            {"type":"number","name":"standards.AutopatchGroup.TestDnfDeferral","label":"Test Ring - Driver & Firmware Deferral (days)","defaultValue":0,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":30,"message":"Maximum value is 30"}}}
            {"type":"number","name":"standards.AutopatchGroup.LastDnfDeferral","label":"Last Ring - Driver & Firmware Deferral (days)","defaultValue":1,"validators":{"min":{"value":0,"message":"Minimum value is 0"},"max":{"value":30,"message":"Maximum value is 30"}}}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-05-27
        POWERSHELLEQUIVALENT
            Autopatch API - POST /api/autoPatch
        RECOMMENDEDBY
        MULTIPLE
            True
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param(
        $Tenant,
        $Settings
    )
    # This autoPatch proxy has been created by Microsoft to facilitate Autopatch group management until native Graph API support is available. It abstracts the underlying Graph API calls and provides a simplified interface for creating and updating Autopatch groups based on the provided settings.

    $AutopatchProxyBase = 'https://intuneautopatchbeta-bwhtaqgefgcyaaa8.westeurope-01.azurewebsites.net/api/autoPatch'

    # Extract settings with defaults
    $GroupName = $Settings.GroupName ?? 'Autopatch default group'
    $TargetOSVersion = $Settings.TargetOSVersion.value ?? $Settings.TargetOSVersion ?? 'Windows 11, version 25H2'
    $EnableDriverUpdate = if ($null -ne $Settings.EnableDriverUpdate) { [bool]$Settings.EnableDriverUpdate } else { $true }
    $InstallWin10OnWin11Ineligible = if ($null -ne $Settings.InstallWin10OnWin11Ineligible) { [bool]$Settings.InstallWin10OnWin11Ineligible } else { $false }

    # Test ring settings
    $TestQualityDeferral = [int]($Settings.TestQualityDeferral ?? 0)
    $TestQualityDeadline = [int]($Settings.TestQualityDeadline ?? 1)
    $TestQualityGracePeriod = [int]($Settings.TestQualityGracePeriod ?? 1)
    $TestFeatureDeferral = [int]($Settings.TestFeatureDeferral ?? 0)
    $TestFeatureDeadline = [int]($Settings.TestFeatureDeadline ?? 5)
    $TestEdgeChannel = $Settings.TestEdgeChannel.value ?? $Settings.TestEdgeChannel ?? 'Beta'
    $TestOfficeChannel = $Settings.TestOfficeChannel.value ?? $Settings.TestOfficeChannel ?? 'MonthlyEnterprise'
    $TestDnfDeferral = [int]($Settings.TestDnfDeferral ?? 0)

    # Last ring settings
    $LastQualityDeferral = [int]($Settings.LastQualityDeferral ?? 1)
    $LastQualityDeadline = [int]($Settings.LastQualityDeadline ?? 2)
    $LastQualityGracePeriod = [int]($Settings.LastQualityGracePeriod ?? 2)
    $LastFeatureDeferral = [int]($Settings.LastFeatureDeferral ?? 0)
    $LastFeatureDeadline = [int]($Settings.LastFeatureDeadline ?? 5)
    $LastEdgeChannel = $Settings.LastEdgeChannel.value ?? $Settings.LastEdgeChannel ?? 'Stable'
    $LastOfficeChannel = $Settings.LastOfficeChannel.value ?? $Settings.LastOfficeChannel ?? 'MonthlyEnterprise'
    $LastDnfDeferral = [int]($Settings.LastDnfDeferral ?? 1)
    $LastOfficeDeferral = [int]($Settings.LastOfficeDeferral ?? 1)
    $LastOfficeDeadline = [int]($Settings.LastOfficeDeadline ?? 2)

    # Get current autopatch groups
    try {
        $CurrentGroups = New-GraphGetRequest -uri $AutopatchProxyBase -tenantid $Tenant -AsApp $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not retrieve Autopatch groups: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    $ExistingGroup = if ($CurrentGroups) {
        @($CurrentGroups) | Where-Object { $_.name -eq $GroupName } | Select-Object -First 1
    }

    # Build the autopatch group body
    $Body = @{
        name                       = $GroupName
        description                = ''
        globalUserManagedAadGroups = @()
        deploymentGroups           = @(
            @{
                userManagedAadGroups          = @()
                name                          = "$GroupName - Test"
                deploymentGroupPolicySettings = @{
                    aadGroupName                    = "$GroupName - Test"
                    deviceConfigurationSetting      = @{
                        updateBehavior            = 'AutoInstallAndRestart'
                        notificationSetting       = 'DefaultNotifications'
                        qualityDeploymentSettings = @{
                            deferral    = $TestQualityDeferral
                            deadline    = $TestQualityDeadline
                            gracePeriod = $TestQualityGracePeriod
                        }
                        featureDeploymentSettings = @{
                            deferral = $TestFeatureDeferral
                            deadline = $TestFeatureDeadline
                        }
                        updateFrequencyUI         = $null
                        installDays               = $null
                        installTime               = $null
                        activeHourEndTime         = $null
                        activeHourStartTime       = $null
                    }
                    featureUpdateAnchorCloudSetting = @{
                        targetOSVersion                                   = $TargetOSVersion
                        installLatestWindows10OnWindows11IneligibleDevice = $InstallWin10OnWin11Ineligible
                    }
                    dnfUpdateCloudSetting           = @{
                        approvalType             = 'Automatic'
                        deploymentDeferralInDays = $TestDnfDeferral
                    }
                    edgeDCv2Setting                 = @{
                        targetChannel = $TestEdgeChannel
                    }
                    officeDCv2Setting               = @{
                        targetChannel           = $TestOfficeChannel
                        deferral                = 0
                        deadline                = 1
                        hideUpdateNotifications = $false
                        enableAutomaticUpdate   = $true
                        hideEnableDisableUpdate = $true
                        enableOfficeMgmt        = $false
                        updatePath              = 'http://officecdn.microsoft.com/pr/55336b82-a18d-4dd6-b5f6-9e5095c314a6'
                    }
                }
            }
            @{
                userManagedAadGroups          = @()
                name                          = "$GroupName - Last"
                deploymentGroupPolicySettings = @{
                    aadGroupName                    = "$GroupName - Last"
                    deviceConfigurationSetting      = @{
                        updateBehavior            = 'AutoInstallAndRestart'
                        notificationSetting       = 'DefaultNotifications'
                        qualityDeploymentSettings = @{
                            deferral    = $LastQualityDeferral
                            deadline    = $LastQualityDeadline
                            gracePeriod = $LastQualityGracePeriod
                        }
                        featureDeploymentSettings = @{
                            deferral = $LastFeatureDeferral
                            deadline = $LastFeatureDeadline
                        }
                        updateFrequencyUI         = $null
                        installDays               = $null
                        installTime               = $null
                        activeHourEndTime         = $null
                        activeHourStartTime       = $null
                    }
                    featureUpdateAnchorCloudSetting = @{
                        targetOSVersion                                   = $TargetOSVersion
                        installLatestWindows10OnWindows11IneligibleDevice = $InstallWin10OnWin11Ineligible
                    }
                    dnfUpdateCloudSetting           = @{
                        approvalType             = 'Automatic'
                        deploymentDeferralInDays = $LastDnfDeferral
                    }
                    edgeDCv2Setting                 = @{
                        targetChannel = $LastEdgeChannel
                    }
                    officeDCv2Setting               = @{
                        targetChannel           = $LastOfficeChannel
                        deferral                = $LastOfficeDeferral
                        deadline                = $LastOfficeDeadline
                        hideUpdateNotifications = $false
                        enableAutomaticUpdate   = $true
                        hideEnableDisableUpdate = $true
                        enableOfficeMgmt        = $false
                        updatePath              = 'http://officecdn.microsoft.com/pr/55336b82-a18d-4dd6-b5f6-9e5095c314a6'
                    }
                }
            }
        )
        type                       = 'User'
        enableDriverUpdate         = $EnableDriverUpdate
        scopeTags                  = @(0)
        enabledContentTypes        = 31
    } | ConvertTo-Json -Compress -Depth 10

    if ($Settings.remediate -eq $true) {
        if ($ExistingGroup) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Autopatch group '$GroupName' already exists, updating." -sev Info
            try {
                $UpdateUri = "$AutopatchProxyBase/$($ExistingGroup.id)"
                New-GraphPOSTRequest -uri $UpdateUri -tenantid $Tenant -body $Body -type PUT
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully updated Autopatch group '$GroupName'." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to update Autopatch group '$GroupName': $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            try {
                New-GraphPOSTRequest -uri $AutopatchProxyBase -tenantid $Tenant -body $Body -type POST
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully created Autopatch group '$GroupName'." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Autopatch group '$GroupName': $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($ExistingGroup) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Autopatch group '$GroupName' is configured." -sev Info
        } else {
            Write-StandardsAlert -message "Autopatch group '$GroupName' is not configured." -object $GroupName `
                -tenant $Tenant -standardName 'AutopatchGroup' -standardId $Settings.standardId
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'AutopatchGroup' -FieldValue ([bool]$ExistingGroup) -StoreAs bool -Tenant $Tenant
    }
}
