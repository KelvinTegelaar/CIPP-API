function Invoke-CIPPStandardIntuneComplianceSettings {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) IntuneComplianceSettings
    .SYNOPSIS
        (Label) InTune Compliance settings
    .DESCRIPTION
        (Helptext) Sets the mark devices with no compliance policy assigned as compliance/non compliant and Compliance status validity period.
        (DocsDescription) Sets the mark devices with no compliance policy assigned as compliance/non compliant and Compliance status validity period.
    .NOTES
        CAT
            InTune Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/settings' -tenantid $Tenant

    if ($null -eq $Settings.secureByDefault) { $Settings.secureByDefault = $true }
    if ($null -eq $Settings.deviceComplianceCheckinThresholdDays) { $Settings.deviceComplianceCheckinThresholdDays = $CurrentState.deviceComplianceCheckinThresholdDays }
    $StateIsCorrect =   ($CurrentState.secureByDefault -eq $Settings.secureByDefault) -and
                        ($CurrentState.deviceComplianceCheckinThresholdDays -eq $Settings.deviceComplianceCheckinThresholdDays)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'InTune Compliance settings is already applied correctly.' -Sev Info
        } else {
            try {
                $GraphRequest = @{
                    tenantID    = $Tenant
                    uri         = "https://graph.microsoft.com/beta/deviceManagement"
                    AsApp       = $true
                    Type        = 'PATCH'
                    ContentType = 'application/json; charset=utf-8'
                    Body        = [pscustomobject]@{
                        settings = [pscustomobject]@{
                            secureByDefault = $Settings.secureByDefault
                            deviceComplianceCheckinThresholdDays = $Settings.deviceComplianceCheckinThresholdDays
                        }
                    } | ConvertTo-Json -Compress
                }
                New-GraphPostRequest @GraphRequest
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully updated InTune Compliance settings.' -Sev Info
            } catch {
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to update InTune Compliance settings." -Sev Error -LogData $_
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'InTune Compliance settings is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'InTune Compliance settings is not enabled.' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'IntuneComplianceSettings' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
