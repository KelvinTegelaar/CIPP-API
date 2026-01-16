function Invoke-CIPPStandardintuneRequireMFA {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) intuneRequireMFA
    .SYNOPSIS
        (Label) Require Multi-factor Authentication to register or join devices with Microsoft Entra
    .DESCRIPTION
        (Helptext) Requires MFA for all users to register devices with Intune. This is useful when not using Conditional Access.
        (DocsDescription) Requires MFA for all users to register devices with Intune. This is useful when not using Conditional Access.
    .NOTES
        CAT
            Intune Standards
        TAG
        EXECUTIVETEXT
            Requires employees to use multi-factor authentication when registering devices for corporate access, adding an extra security layer to prevent unauthorized device enrollment. This helps ensure only legitimate users can connect their devices to company systems.
        IMPACT
            Medium Impact
        ADDEDDATE
            2023-10-23
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
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the intuneRequireMFA state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($PreviousSetting.multiFactorAuthConfiguration -eq 'required') {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Require to use MFA when joining/registering Entra Devices is already enabled.' -sev Info
        } else {
            try {
                $NewSetting = $PreviousSetting
                $NewSetting.multiFactorAuthConfiguration = 'required'
                $NewBody = ConvertTo-Json -Compress -InputObject $NewSetting -Depth 10
                New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Set required to use MFA when joining/registering Entra Devices' -sev Info
                $PreviousSetting.multiFactorAuthConfiguration = 'required'
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set require to use MFA when joining/registering Entra Devices: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($PreviousSetting.multiFactorAuthConfiguration -eq 'required') {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Require to use MFA when joining/registering Entra Devices is enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'Require to use MFA when joining/registering Entra Devices is not enabled' -object $PreviousSetting -tenant $Tenant -standardName 'intuneRequireMFA' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Require to use MFA when joining/registering Entra Devices is not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $RequireMFA = if ($PreviousSetting.multiFactorAuthConfiguration -eq 'required') { $true } else { $false }

        $CurrentValue = @{
            multiFactorAuthConfiguration = $PreviousSetting.multiFactorAuthConfiguration
        }
        $ExpectedValue = @{
            multiFactorAuthConfiguration = 'required'
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.intuneRequireMFA' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'intuneRequireMFA' -FieldValue $RequireMFA -StoreAs bool -Tenant $Tenant
    }
}
