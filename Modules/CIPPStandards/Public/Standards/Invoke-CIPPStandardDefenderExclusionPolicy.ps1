function Invoke-CIPPStandardDefenderExclusionPolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DefenderExclusionPolicy
    .SYNOPSIS
        (Label) Defender AV Exclusion Policy
    .DESCRIPTION
        (Helptext) Deploys and enforces a Microsoft Defender Antivirus exclusion policy via Intune. Allows you to exclude specific file extensions, file paths, and processes from Defender scanning.
        (DocsDescription) Deploys a standardised Microsoft Defender Antivirus exclusion policy through Intune. This standard manages exclusions for file extensions (e.g. .log, .tmp), file paths (e.g. C:\Temp), and processes (e.g. notepad.exe) that should be skipped during Defender scanning. Useful for excluding known-safe applications or paths that cause performance issues or false positives. The exclusion policy is created as a separate Intune configuration policy and can be assigned to users, devices, or both.
    .NOTES
        CAT
            Defender Standards
        TAG
            "defender_exclusions"
            "defender_av_exclusions"
            "intune_endpoint_protection"
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.DefenderExclusionPolicy.excludedExtensions","label":"Excluded Extensions (comma-separated, e.g. txt,log,tmp)","required":false}
            {"type":"textField","name":"standards.DefenderExclusionPolicy.excludedPaths","label":"Excluded Paths (comma-separated, e.g. C:\\Temp,C:\\Program Files\\App)","required":false}
            {"type":"textField","name":"standards.DefenderExclusionPolicy.excludedProcesses","label":"Excluded Processes (comma-separated, e.g. notepad.exe,chrome.exe)","required":false}
            {"type":"radio","name":"standards.DefenderExclusionPolicy.AssignTo","label":"Policy Assignment","options":[{"label":"Do not assign","value":"none"},{"label":"All users","value":"allLicensedUsers"},{"label":"All devices","value":"AllDevices"},{"label":"All users and devices","value":"AllDevicesAndUsers"}]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-04-02
        POWERSHELLEQUIVALENT
            Graph API - deviceManagement/configurationPolicies
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    $PolicyName = 'Default AV Exclusion Policy'

    # Setting definition IDs for exclusion types
    $ExtensionsDefId = 'device_vendor_msft_policy_config_defender_excludedextensions'
    $PathsDefId = 'device_vendor_msft_policy_config_defender_excludedpaths'
    $ProcessesDefId = 'device_vendor_msft_policy_config_defender_excludedprocesses'

    # Parse expected values from comma-separated settings
    $ExpectedExtensions = @()
    $ExpectedPaths = @()
    $ExpectedProcesses = @()
    if ($Settings.excludedExtensions) {
        $ExpectedExtensions = @(($Settings.excludedExtensions -replace ' ', '') -split ',' | Where-Object { $_ -and $_.Trim() } | Sort-Object)
    }
    if ($Settings.excludedPaths) {
        $ExpectedPaths = @(($Settings.excludedPaths -replace '^\s+|\s+$', '') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)
    }
    if ($Settings.excludedProcesses) {
        $ExpectedProcesses = @(($Settings.excludedProcesses -replace '^\s+|\s+$', '') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)
    }

    $ExpectedValue = [PSCustomObject]@{
        PolicyExists       = $true
        excludedExtensions = ($ExpectedExtensions -join ',')
        excludedPaths      = ($ExpectedPaths -join ',')
        excludedProcesses  = ($ExpectedProcesses -join ',')
    }

    # Check existing policies
    try {
        $ExistingPolicies = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve configuration policies: $ErrorMessage" -sev Error
        return
    }

    $ExistingPolicy = $ExistingPolicies | Where-Object { $_.Name -eq $PolicyName } | Select-Object -First 1
    $PolicyExists = $null -ne $ExistingPolicy

    # Parse current exclusion settings
    $CurrentExtensions = @()
    $CurrentPaths = @()
    $CurrentProcesses = @()
    if ($PolicyExists) {
        try {
            $PolicyDetail = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ExistingPolicy.id)')?`$expand=settings" -tenantid $Tenant
            foreach ($setting in $PolicyDetail.settings) {
                $instance = $setting.settingInstance
                switch ($instance.settingDefinitionId) {
                    $ExtensionsDefId {
                        $CurrentExtensions = @($instance.simpleSettingCollectionValue | ForEach-Object { $_.value } | Sort-Object)
                    }
                    $PathsDefId {
                        $CurrentPaths = @($instance.simpleSettingCollectionValue | ForEach-Object { $_.value } | Sort-Object)
                    }
                    $ProcessesDefId {
                        $CurrentProcesses = @($instance.simpleSettingCollectionValue | ForEach-Object { $_.value } | Sort-Object)
                    }
                }
            }
        } catch {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to read Exclusion Policy settings: $($_.Exception.Message)" -sev Warning
        }
    }

    $CurrentValue = [PSCustomObject]@{
        PolicyExists       = $PolicyExists
        excludedExtensions = ($CurrentExtensions -join ',')
        excludedPaths      = ($CurrentPaths -join ',')
        excludedProcesses  = ($CurrentProcesses -join ',')
    }

    # Compare sorted arrays
    $StateIsCorrect = $PolicyExists
    if ($PolicyExists) {
        if ($null -ne (Compare-Object -ReferenceObject $ExpectedExtensions -DifferenceObject $CurrentExtensions -SyncWindow 0)) { $StateIsCorrect = $false }
        if ($StateIsCorrect -and $null -ne (Compare-Object -ReferenceObject $ExpectedPaths -DifferenceObject $CurrentPaths -SyncWindow 0)) { $StateIsCorrect = $false }
        if ($StateIsCorrect -and $null -ne (Compare-Object -ReferenceObject $ExpectedProcesses -DifferenceObject $CurrentProcesses -SyncWindow 0)) { $StateIsCorrect = $false }
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender Exclusion Policy already correctly configured' -sev Info
        } else {
            try {
                # Delete existing drifted policy so the helper can recreate
                if ($PolicyExists) {
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ExistingPolicy.id)')" -tenantid $Tenant -type DELETE
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Deleted drifted Defender Exclusion Policy for recreation' -sev Info
                }

                $ExclusionSettings = @{
                    AssignTo = $Settings.AssignTo ?? 'none'
                }
                if ($ExpectedExtensions.Count -gt 0) { $ExclusionSettings['excludedExtensions'] = $ExpectedExtensions }
                if ($ExpectedPaths.Count -gt 0) { $ExclusionSettings['excludedPaths'] = $ExpectedPaths }
                if ($ExpectedProcesses.Count -gt 0) { $ExclusionSettings['excludedProcesses'] = $ExpectedProcesses }

                $Result = Set-CIPPDefenderExclusionPolicy -TenantFilter $Tenant -DefenderExclusions $ExclusionSettings -APIName 'Standards'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message $Result -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to deploy Defender Exclusion Policy: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender Exclusion Policy is correctly configured' -sev Info
        } else {
            Write-StandardsAlert -message 'Defender Exclusion Policy is not correctly configured' -object $CurrentValue -tenant $Tenant -standardName 'DefenderExclusionPolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Defender Exclusion Policy is not correctly configured' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.DefenderExclusionPolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DefenderExclusionPolicy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
