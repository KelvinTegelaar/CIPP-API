function Invoke-CIPPStandardSecureScoreRemediation {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SecureScoreRemediation
    .SYNOPSIS
        (Label) Update Secure Score Control Profiles
    .DESCRIPTION
        (Helptext) Allows bulk updating of Secure Score control profiles across tenants. Select controls and assign them to different states: Default, Ignored, Third-Party, or Reviewed.
        (DocsDescription) Allows bulk updating of Secure Score control profiles across tenants. Select controls and assign them to different states: Default, Ignored, Third-Party, or Reviewed.
    .NOTES
        CAT
            Global Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.SecureScoreRemediation.Default","label":"Controls to set to Default","api":{"url":"/secureScore.json","labelField":"title","valueField":"id"}}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.SecureScoreRemediation.Ignored","label":"Controls to set to Ignored","api":{"url":"/secureScore.json","labelField":"title","valueField":"id"}}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.SecureScoreRemediation.ThirdParty","label":"Controls to set to Third-Party","api":{"url":"/secureScore.json","labelField":"title","valueField":"id"}}
            {"type":"autoComplete","multiple":true,"required":false,"creatable":true,"name":"standards.SecureScoreRemediation.Reviewed","label":"Controls to set to Reviewed","api":{"url":"/secureScore.json","labelField":"title","valueField":"id"}}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-11-19
        POWERSHELLEQUIVALENT
            New-GraphPostRequest to /beta/security/secureScoreControlProfiles/{id}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)


    # Get current secure score controls
    try {
        $CurrentControls = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/secureScoreControlProfiles' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not retrieve Secure Score controls for $Tenant. Error: $ErrorMessage" -sev Error
        return
    }

    # Build list of controls with their desired states
    $ControlsToUpdate = [System.Collections.Generic.List[object]]::new()

    # Process Default controls
    $DefaultControls = $Settings.Default.value ?? $Settings.Default
    if ($DefaultControls) {
        foreach ($ControlName in $DefaultControls) {
            $ControlsToUpdate.Add(@{
                    ControlName = $ControlName
                    State       = 'default'
                    Reason      = 'Default'
                })
        }
    }

    # Process Ignored controls
    $IgnoredControls = $Settings.Ignored.value ?? $Settings.Ignored
    if ($IgnoredControls) {
        foreach ($ControlName in $IgnoredControls) {
            $ControlsToUpdate.Add(@{
                    ControlName = $ControlName
                    State       = 'ignored'
                    Reason      = 'Ignored'
                })
        }
    }

    # Process ThirdParty controls
    $ThirdPartyControls = $Settings.ThirdParty.value ?? $Settings.ThirdParty
    if ($ThirdPartyControls) {
        foreach ($ControlName in $ThirdPartyControls) {
            $ControlsToUpdate.Add(@{
                    ControlName = $ControlName
                    State       = 'thirdParty'
                    Reason      = 'ThirdParty'
                })
        }
    }

    # Process Reviewed controls
    $ReviewedControls = $Settings.Reviewed.value ?? $Settings.Reviewed
    if ($ReviewedControls) {
        foreach ($ControlName in $ReviewedControls) {
            $ControlsToUpdate.Add(@{
                    ControlName = $ControlName
                    State       = 'reviewed'
                    Reason      = 'Reviewed'
                })
        }
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Processing Secure Score control updates'

        foreach ($Control in $ControlsToUpdate) {
            # Skip if this is a Defender control (starts with scid_)
            if ($Control.ControlName -match '^scid_') {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Skipping Defender control $($Control.ControlName) - cannot be updated via this API" -sev Info
                continue
            }

            # Build the request body
            $Body = @{
                state             = $Control.State
                comment           = $Control.Reason
                vendorInformation = @{
                    vendor   = 'Microsoft'
                    provider = 'SecureScore'
                }
            }

            try {
                $CurrentControl = $CurrentControls | Where-Object { $_.id -eq $Control.ControlName }

                # Check if already in desired state
                if ($CurrentControl.state -eq $Control.State) {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Control $($Control.ControlName) is already in state $($Control.State)" -sev Info
                } else {
                    # Update the control
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/security/secureScoreControlProfiles/$($Control.ControlName)" -tenantid $Tenant -type PATCH -Body (ConvertTo-Json -InputObject $Body -Compress)
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully set control $($Control.ControlName) to $($Control.State)" -sev Info
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set control $($Control.ControlName) to $($Control.State). Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        $AlertMessages = [System.Collections.Generic.List[string]]::new()

        foreach ($Control in $ControlsToUpdate) {
            if ($Control.ControlName -match '^scid_') {
                continue
            }

            $CurrentControl = $CurrentControls | Where-Object { $_.id -eq $Control.ControlName }

            if ($CurrentControl) {
                if ($CurrentControl.state -eq $Control.State) {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Control $($Control.ControlName) is in expected state: $($Control.State)" -sev Info
                } else {
                    $AlertMessage = "Control $($Control.ControlName) is in state $($CurrentControl.state), expected $($Control.State)"
                    $AlertMessages.Add($AlertMessage)
                    Write-LogMessage -API 'Standards' -tenant $tenant -message $AlertMessage -sev Alert
                }
            } else {
                $AlertMessage = "Control $($Control.ControlName) not found in tenant"
                $AlertMessages.Add($AlertMessage)
                Write-LogMessage -API 'Standards' -tenant $tenant -message $AlertMessage -sev Warning
            }
        }

        if ($AlertMessages.Count -gt 0) {
            Write-StandardsAlert -message 'Secure Score controls not in expected state' -object @{Issues = $AlertMessages.ToArray() } -tenant $Tenant -standardName 'SecureScoreRemediation' -standardId $Settings.standardId
        }
    }

    if ($Settings.report -eq $true) {
        $ReportData = [System.Collections.Generic.List[object]]::new()

        foreach ($Control in $ControlsToUpdate) {
            if ($Control.ControlName -match '^scid_') {
                continue
            }

            $CurrentControl = $CurrentControls | Where-Object { $_.id -eq $Control.ControlName }
            $LatestState = ($CurrentControl.controlStateUpdates | Select-Object -Last 1).state
            if ($LatestState -ne $Control.State) {
                $ReportData.Add(@{
                        ControlName  = $Control.ControlName
                        CurrentState = $LatestState
                        DesiredState = $Control.State
                        InCompliance = $false
                    })
            }
        }
        if ($ReportData.count -eq 0) {
            $ReportData = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.SecureScoreRemediation' -FieldValue $ReportData -Tenant $tenant
        Add-CIPPBPAField -FieldName 'SecureScoreRemediation' -FieldValue $ReportData -StoreAs json -Tenant $tenant
    }
}
