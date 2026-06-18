function Invoke-CIPPStandardCopilotSettings {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) CopilotSettings
    .SYNOPSIS
        (Label) Configure Microsoft 365 Copilot policy settings
    .DESCRIPTION
        (Helptext) Configures Microsoft 365 Copilot tenant policy settings: Copilot Chat pinning, blocking Copilot access to open content, Designer image generation, web search, and admin-center Copilot. Each setting can be left unconfigured, enabled, or disabled. These settings are managed through the Copilot policy service (Cloud Policy / Intune) and are applied at the tenant level.
        (DocsDescription) Manages Microsoft 365 Copilot admin policy settings via the `/copilot/admin/policySettings` Microsoft Graph API (beta). Each of the five supported settings can be independently set or left unmanaged using the "Do not configure" option. NOTE: this API currently requires delegated authentication and supports only tenant-level policies; settings scoped to group-level policies return an error and are skipped. The exact accepted value per setting is a string (commonly "1"/"0") and should be validated against a Copilot-licensed tenant.
    .NOTES
        CAT
            Copilot (M365) Standards
        TAG
        EXECUTIVETEXT
            Provides centralized governance of Microsoft 365 Copilot capabilities across the organization. Administrators can control whether Copilot Chat is pinned for users, whether Copilot can access open files, and whether features such as image generation and web search are available, helping balance employee productivity with data governance and compliance requirements.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Pin Microsoft 365 Copilot Chat","name":"standards.CopilotSettings.copilotChatPinning","options":[{"label":"Do not configure","value":"donotconfigure"},{"label":"Enabled","value":"1"},{"label":"Disabled","value":"0"}]}
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Copilot Access to Open Content","name":"standards.CopilotSettings.blockAccessToOpenFiles","options":[{"label":"Do not configure","value":"donotconfigure"},{"label":"Block open content","value":"1"},{"label":"Allow open content","value":"0"}]}
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Designer Image Generation","name":"standards.CopilotSettings.imageGeneration","options":[{"label":"Do not configure","value":"donotconfigure"},{"label":"Enabled","value":"1"},{"label":"Disabled","value":"0"}]}
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Web Search in Copilot","name":"standards.CopilotSettings.allowWebSearch","options":[{"label":"Do not configure","value":"donotconfigure"},{"label":"Enabled","value":"1"},{"label":"Disabled","value":"0"}]}
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Admin Copilot in Microsoft 365 Admin Center","name":"standards.CopilotSettings.allowInAdminCenters","options":[{"label":"Do not configure","value":"donotconfigure"},{"label":"Enabled","value":"1"},{"label":"Disabled","value":"0"}]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-06-09
        POWERSHELLEQUIVALENT
            Graph API: PATCH /beta/copilot/admin/policySettings/{id}
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    # Supported Copilot policy settings. 'Id' is the Graph policySettings identifier; 'Key' is the CIPP setting field name.
    $CopilotPolicySettings = @(
        @{ Key = 'copilotChatPinning'; Id = 'microsoft.copilot.copilotchatpinning'; Label = 'Pin Microsoft 365 Copilot Chat' }
        @{ Key = 'blockAccessToOpenFiles'; Id = 'microsoft.copilot.blockaccesstoopenfiles'; Label = 'Block Copilot Access to Open Content' }
        @{ Key = 'imageGeneration'; Id = 'microsoft.copilot.imagegeneration'; Label = 'Designer Image Generation' }
        @{ Key = 'allowWebSearch'; Id = 'microsoft.copilot.allowwebsearch'; Label = 'Allow web search in Copilot' }
        @{ Key = 'allowInAdminCenters'; Id = 'microsoft.copilot.allowinadmincenters'; Label = 'Admin Copilot in Microsoft 365 Admin Center' }
    )

    # Determine which settings the admin explicitly configured (anything other than blank / 'donotconfigure')
    $ConfiguredSettings = foreach ($Setting in $CopilotPolicySettings) {
        $DesiredValue = $Settings.$($Setting.Key).value ?? $Settings.$($Setting.Key)
        if ([string]::IsNullOrWhiteSpace($DesiredValue) -or $DesiredValue -eq 'donotconfigure') { continue }
        [PSCustomObject]@{
            Key     = $Setting.Key
            Id      = $Setting.Id
            Label   = $Setting.Label
            Desired = [string]$DesiredValue
        }
    }

    if (-not $ConfiguredSettings -or @($ConfiguredSettings).Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'CopilotSettings: No Copilot settings configured, skipping.' -sev Info
        return
    }

    # Read current state for each configured setting.
    # The Copilot policySettings API currently requires delegated auth (no -AsApp). The entity also
    # carries a scalar 'value' property that is data rather than a collection envelope, so
    # -SkipValueExtraction returns the entity intact.
    $ComplianceResults = foreach ($Setting in $ConfiguredSettings) {
        try {
            $Current = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/copilot/admin/policySettings/$($Setting.Id)" -tenantid $Tenant -SkipValueExtraction
            [PSCustomObject]@{
                Key          = $Setting.Key
                Id           = $Setting.Id
                Label        = $Setting.Label
                Desired      = $Setting.Desired
                CurrentValue = $Current.value
                PolicyId     = $Current.policyId
                IsCompliant  = ([string]$Current.value -eq $Setting.Desired)
                Error        = $null
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "CopilotSettings: Could not retrieve '$($Setting.Label)'. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            [PSCustomObject]@{
                Key          = $Setting.Key
                Id           = $Setting.Id
                Label        = $Setting.Label
                Desired      = $Setting.Desired
                CurrentValue = $null
                PolicyId     = $null
                IsCompliant  = $false
                Error        = $ErrorMessage.NormalizedError
            }
        }
    }

    if ($Settings.remediate -eq $true) {
        foreach ($Result in $ComplianceResults) {
            if ($Result.Error) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "CopilotSettings: Skipping remediation of '$($Result.Label)' due to a read error." -sev Warning
                continue
            }
            if ($Result.IsCompliant) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "CopilotSettings: '$($Result.Label)' is already set to '$($Result.Desired)'." -sev Info
                continue
            }
            try {
                $Body = [pscustomobject]@{ value = $Result.Desired } | ConvertTo-Json -Compress
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/copilot/admin/policySettings/$($Result.Id)" -tenantid $Tenant -type PATCH -body $Body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "CopilotSettings: Set '$($Result.Label)' to '$($Result.Desired)' (was '$($Result.CurrentValue)')." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "CopilotSettings: Failed to set '$($Result.Label)' to '$($Result.Desired)'. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        $NonCompliant = @($ComplianceResults | Where-Object { -not $_.IsCompliant })
        if ($NonCompliant.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'CopilotSettings: All configured Copilot settings are compliant.' -sev Info
        } else {
            $AlertDetails = foreach ($Result in $NonCompliant) {
                [PSCustomObject]@{
                    Setting = $Result.Label
                    Current = $Result.CurrentValue
                    Desired = $Result.Desired
                }
            }
            Write-StandardsAlert -message "CopilotSettings: $($NonCompliant.Count) Copilot setting(s) not compliant: $(($NonCompliant.Label) -join ', ')" -object $AlertDetails -tenant $Tenant -standardName 'CopilotSettings' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "CopilotSettings: $($NonCompliant.Count) Copilot setting(s) not compliant." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentState = @{}
        $ExpectedState = @{}
        foreach ($Result in $ComplianceResults) {
            $CurrentState[$Result.Key] = $Result.CurrentValue
            $ExpectedState[$Result.Key] = $Result.Desired
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.CopilotSettings' -CurrentValue ([PSCustomObject]$CurrentState) -ExpectedValue ([PSCustomObject]$ExpectedState) -TenantFilter $Tenant
        $AllCompliant = -not ($ComplianceResults | Where-Object { -not $_.IsCompliant })
        Add-CIPPBPAField -FieldName 'CopilotSettings' -FieldValue ([bool]$AllCompliant) -StoreAs bool -Tenant $Tenant
    }
}
