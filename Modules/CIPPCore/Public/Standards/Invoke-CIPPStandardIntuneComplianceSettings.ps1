function Invoke-CIPPStandardIntuneComplianceSettings {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) IntuneComplianceSettings
    .SYNOPSIS
        (Label) Set Intune Compliance Settings
    .DESCRIPTION
        (Helptext) Sets the mark devices with no compliance policy assigned as compliance/non compliant and Compliance status validity period.
        (DocsDescription) Sets the mark devices with no compliance policy assigned as compliance/non compliant and Compliance status validity period.
    .NOTES
        CAT
            Intune Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","required":true,"multiple":false,"creatable":false,"name":"standards.IntuneComplianceSettings.secureByDefault","label":"Mark devices with no compliance policy as","options":[{"label":"Compliant","value":"false"},{"label":"Non-Compliant","value":"true"}]}
            {"type":"number","name":"standards.IntuneComplianceSettings.deviceComplianceCheckinThresholdDays","label":"Compliance status validity period (days)"}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-11-12
        POWERSHELLEQUIVALENT
            
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/intune-standards#low-impact
    #>

    param($Tenant, $Settings)

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/settings' -tenantid $Tenant

    if ($null -eq $Settings.deviceComplianceCheckinThresholdDays) { $Settings.deviceComplianceCheckinThresholdDays = $CurrentState.deviceComplianceCheckinThresholdDays }
    $SecureByDefault = $Settings.secureByDefault.value ?? $Settings.secureByDefault
    $StateIsCorrect = ($CurrentState.secureByDefault -eq $SecureByDefault) -and
                        ($CurrentState.deviceComplianceCheckinThresholdDays -eq $Settings.deviceComplianceCheckinThresholdDays)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'InTune Compliance settings is already applied correctly.' -Sev Info
        } else {
            try {
                $GraphRequest = @{
                    tenantID    = $Tenant
                    uri         = 'https://graph.microsoft.com/beta/deviceManagement'
                    AsApp       = $true
                    Type        = 'PATCH'
                    ContentType = 'application/json; charset=utf-8'
                    Body        = [pscustomobject]@{
                        settings = [pscustomobject]@{
                            secureByDefault                      = $SecureByDefault
                            deviceComplianceCheckinThresholdDays = $Settings.deviceComplianceCheckinThresholdDays
                        }
                    } | ConvertTo-Json -Compress
                }
                New-GraphPostRequest @GraphRequest
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully updated InTune Compliance settings.' -Sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Failed to update InTune Compliance settings.' -Sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'InTune Compliance settings is enabled.' -Sev Info
        } else {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'InTune Compliance settings is not enabled.' -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'IntuneComplianceSettings' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
