function Invoke-CIPPStandardintuneRequireMFA {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) intuneRequireMFA
    .SYNOPSIS
        (Label) Configure MFA requirement to register or join devices with Microsoft Entra
    .DESCRIPTION
        (Helptext) Sets whether MFA is required to register or join devices with Microsoft Entra. Microsoft recommends enforcing this with a Conditional Access policy for the 'Register or join devices' user action and setting this to Not required. Setting Not required without such a policy leaves device registration without MFA.
        (DocsDescription) Sets whether MFA is required to register or join devices with Microsoft Entra. Microsoft recommends enforcing this with a Conditional Access policy for the 'Register or join devices' user action and setting this to Not required. Setting Not required without such a policy leaves device registration without MFA.
    .NOTES
        CAT
            Intune Standards
        TAG
            "ZTNA21872"
        EXECUTIVETEXT
            Controls whether employees must use multi-factor authentication when registering or joining devices through the Entra device setting. Microsoft recommends enforcing this through Conditional Access instead, which allows exceptions for scenarios such as meeting room equipment while still protecting device enrollment.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"required":true,"label":"MFA to register or join devices","name":"standards.intuneRequireMFA.state","options":[{"label":"Required","value":"required"},{"label":"Not required (enforce with Conditional Access)","value":"notRequired"}]}
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
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    try {
        $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the intuneRequireMFA state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    # Backwards compat: templates saved before the Required/Not required option have no state, keep the original behaviour
    $Wanted = $Settings.state.value ?? $Settings.state ?? 'required'

    if ($Settings.remediate -eq $true) {
        if ($PreviousSetting.multiFactorAuthConfiguration -eq $Wanted) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "MFA when joining/registering Entra Devices is already set to $Wanted." -sev Info
        } else {
            try {
                $NewSetting = $PreviousSetting
                $NewSetting.multiFactorAuthConfiguration = $Wanted
                $NewBody = ConvertTo-Json -Compress -InputObject $NewSetting -Depth 10
                New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set MFA when joining/registering Entra Devices to $Wanted" -sev Info
                $PreviousSetting.multiFactorAuthConfiguration = $Wanted
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set MFA when joining/registering Entra Devices to $($Wanted): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($PreviousSetting.multiFactorAuthConfiguration -eq $Wanted) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "MFA when joining/registering Entra Devices is set to $Wanted." -sev Info
        } else {
            Write-StandardsAlert -message "MFA when joining/registering Entra Devices is not set to $Wanted" -object $PreviousSetting -tenant $Tenant -standardName 'intuneRequireMFA' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "MFA when joining/registering Entra Devices is not set to $Wanted." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            multiFactorAuthConfiguration = $PreviousSetting.multiFactorAuthConfiguration
        }
        $ExpectedValue = @{
            multiFactorAuthConfiguration = $Wanted
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.intuneRequireMFA' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
