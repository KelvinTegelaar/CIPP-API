function Invoke-CIPPStandardSecureScoreRemediation {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SecureScoreRemediation
    .SYNOPSIS
        (Label) Update Secure Score Control Profiles
    .DESCRIPTION
        (Helptext) Allows bulk updating of Secure Score control profiles across tenants. Configure controls as resolved, ignored, or third-party mitigated to accurately reflect your security posture.
        (DocsDescription) Enables automated or template-based updates to Microsoft Secure Score recommendations. This is particularly useful for MSPs managing multiple tenants, allowing you to mark controls as "Third-party mitigation" (e.g., when using Mimecast, IronScales, or other third-party security tools) or set them to other states in bulk. This ensures Secure Scores accurately reflect each tenant's true security posture without repetitive manual updates.
    .NOTES
        CAT
            Global Standards
        TAG
            "lowimpact"
        EXECUTIVETEXT
            Automates the management of Secure Score control profiles by allowing bulk updates across tenants. This ensures accurate representation of security posture when using third-party security tools or when certain controls need to be marked as resolved or ignored, significantly reducing manual administrative overhead for MSPs managing multiple clients.
        ADDEDCOMPONENT
            {"type":"input","name":"standards.SecureScoreRemediation.Controls","label":"Control Updates (JSON array)","placeholder":"[{\"ControlName\":\"example\",\"State\":\"thirdPartyMitigation\",\"Reason\":\"Using third-party tool\"}]"}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-11-19
        POWERSHELLEQUIVALENT
            New-GraphPostRequest to /beta/security/secureScoreControlProfiles/{id}
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    
    # Validate that Controls array exists and is not empty
    if (-not $Settings.Controls -or $Settings.Controls.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'No controls specified for Secure Score remediation. Skipping.' -sev Info
        return
    }

    # Process controls from settings
    # Settings.Controls should be an array of objects with ControlName, State, Reason, and optionally VendorInformation
    $Controls = $Settings.Controls
    if ($Controls -is [string]) {
        try {
            $Controls = $Controls | ConvertFrom-Json
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to parse Controls JSON: $ErrorMessage" -sev Error
            return
        }
    }

    # Get current secure score controls
    try {
        $CurrentControls = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/secureScoreControlProfiles' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not retrieve Secure Score controls for $Tenant. Error: $ErrorMessage" -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Processing Secure Score control updates'
        
        foreach ($Control in $Controls) {
            # Skip if this is a Defender control (starts with scid_)
            if ($Control.ControlName -match '^scid_') {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Skipping Defender control $($Control.ControlName) - cannot be updated via this API" -sev Info
                continue
            }

            # Validate required fields
            if (-not $Control.ControlName -or -not $Control.State) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Skipping control update - ControlName and State are required" -sev Warning
                continue
            }

            # Build the request body
            $Body = @{
                state = $Control.State
            }
            
            if ($Control.Reason) {
                $Body.comment = $Control.Reason
            }
            
            if ($Control.VendorInformation) {
                $Body.vendorInformation = $Control.VendorInformation
            }

            try {
                $CurrentControl = $CurrentControls | Where-Object { $_.id -eq $Control.ControlName }
                
                if (-not $CurrentControl) {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Control $($Control.ControlName) not found in tenant" -sev Warning
                    continue
                }

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
        $AlertMessages = @()
        
        foreach ($Control in $Controls) {
            if ($Control.ControlName -match '^scid_') {
                continue
            }
            
            $CurrentControl = $CurrentControls | Where-Object { $_.id -eq $Control.ControlName }
            
            if ($CurrentControl) {
                if ($CurrentControl.state -eq $Control.State) {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Control $($Control.ControlName) is in expected state: $($Control.State)" -sev Info
                } else {
                    $AlertMessage = "Control $($Control.ControlName) is in state $($CurrentControl.state), expected $($Control.State)"
                    $AlertMessages += $AlertMessage
                    Write-LogMessage -API 'Standards' -tenant $tenant -message $AlertMessage -sev Alert
                }
            } else {
                $AlertMessage = "Control $($Control.ControlName) not found in tenant"
                $AlertMessages += $AlertMessage
                Write-LogMessage -API 'Standards' -tenant $tenant -message $AlertMessage -sev Warning
            }
        }
        
        if ($AlertMessages.Count -gt 0) {
            Write-StandardsAlert -message "Secure Score controls not in expected state" -object @{Issues = $AlertMessages} -tenant $Tenant -standardName 'SecureScoreRemediation' -standardId $Settings.standardId
        }
    }

    if ($Settings.report -eq $true) {
        $ReportData = @()
        
        foreach ($Control in $Controls) {
            if ($Control.ControlName -match '^scid_') {
                continue
            }
            
            $CurrentControl = $CurrentControls | Where-Object { $_.id -eq $Control.ControlName }
            
            if ($CurrentControl) {
                $ReportData += @{
                    ControlName = $Control.ControlName
                    CurrentState = $CurrentControl.state
                    DesiredState = $Control.State
                    InCompliance = ($CurrentControl.state -eq $Control.State)
                }
            } else {
                $ReportData += @{
                    ControlName = $Control.ControlName
                    CurrentState = 'Not Found'
                    DesiredState = $Control.State
                    InCompliance = $false
                }
            }
        }
        
        Set-CIPPStandardsCompareField -FieldName 'standards.SecureScoreRemediation' -FieldValue $ReportData -Tenant $tenant
        Add-CIPPBPAField -FieldName 'SecureScoreRemediation' -FieldValue $ReportData -StoreAs json -Tenant $tenant
    }
}
