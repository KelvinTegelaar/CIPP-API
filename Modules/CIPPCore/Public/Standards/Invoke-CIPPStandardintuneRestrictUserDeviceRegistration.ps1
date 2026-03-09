function Invoke-CIPPStandardintuneRestrictUserDeviceRegistration {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) intuneRestrictUserDeviceRegistration
    .SYNOPSIS
        (Label) Configure user restriction for Entra device registration
    .DESCRIPTION
        (Helptext) Controls whether users can register devices with Entra.
        (DocsDescription) Configures whether users can register devices with Entra. When disabled, users are unable to register devices with Entra.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Controls whether employees can register their devices for corporate access. Disabling user device registration prevents unauthorized or unmanaged devices from connecting to company resources, enhancing overall security posture.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.intuneRestrictUserDeviceRegistration.disableUserDeviceRegistration","label":"Disable users from registering devices","defaultValue":true}
        IMPACT
            High Impact
        ADDEDDATE
            2026-03-05
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyDeviceRegistrationPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    try {
        $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the intuneRestrictUserDeviceRegistration state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }
    # Current M365 Config
    $CurrentOdataType = $PreviousSetting.azureADJoin.allowedToJoin.'@odata.type'

    # Standards Config
    $DisableUserDeviceRegistration = [bool]$Settings.disableUserDeviceRegistration

    # State comparison
    $DesiredOdataType = if ($DisableUserDeviceRegistration) { '#microsoft.graph.noDeviceRegistrationMembership' } else { '#microsoft.graph.allDeviceRegistrationMembership' }
    $CurrentDisableUserDeviceRegistration = ($CurrentOdataType -eq '#microsoft.graph.noDeviceRegistrationMembership')
    $StateIsCorrect = ($CurrentOdataType -eq $DesiredOdataType)
    $DesiredStateText = if ($DisableUserDeviceRegistration) { 'disabled' } else { 'enabled' }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Device registration restriction is already configured (registering users allowed to join: $DesiredStateText)." -sev Info
        } else {
            try {
                $PreviousSetting.azureADJoin.allowedToJoin = @{ '@odata.type' = $DesiredOdataType; users = $null; groups = $null }
                $NewBody = ConvertTo-Json -Compress -InputObject $PreviousSetting -Depth 10
                New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
                $CurrentOdataType = $DesiredOdataType
                $CurrentDisableUserDeviceRegistration = ($CurrentOdataType -eq '#microsoft.graph.noDeviceRegistrationMembership')
                $StateIsCorrect = ($CurrentOdataType -eq $DesiredOdataType)
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set device registration restriction (registering users allowed to join: $DesiredStateText)." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set device registration restriction (registering users allowed to join: $DesiredStateText). Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Device registration restriction is configured as expected (registering users allowed to join: $DesiredStateText)." -sev Info
        } else {
            Write-StandardsAlert -message "Device registration restriction is not configured as expected (registering users allowed to join: $DesiredStateText)" -object @{ current = @{ disableUserDeviceRegistration = $CurrentDisableUserDeviceRegistration }; desired = @{ disableUserDeviceRegistration = $DisableUserDeviceRegistration } } -tenant $Tenant -standardName 'intuneRestrictUserDeviceRegistration' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Device registration restriction is not configured as expected (registering users allowed to join: $DesiredStateText)." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            disableUserDeviceRegistration = $CurrentDisableUserDeviceRegistration
        }
        $ExpectedValue = @{
            disableUserDeviceRegistration = $DisableUserDeviceRegistration
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.intuneRestrictUserDeviceRegistration' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'intuneRestrictUserDeviceRegistration' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
