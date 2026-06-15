function Invoke-CIPPStandardintuneRestrictUserDeviceJoin {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) intuneRestrictUserDeviceJoin
    .SYNOPSIS
        (Label) Configure user restriction for Entra device join
    .DESCRIPTION
        (Helptext) Controls whether users can join devices to Entra.
        (DocsDescription) Configures whether users can join devices to Entra. When disabled, users are unable to Entra-join devices, which prevents them from creating new Entra-joined (cloud-managed) device identities.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Controls whether employees can join their devices to the corporate Entra directory. Disabling user device join prevents unauthorized or unmanaged devices from becoming corporate-managed identities, enhancing overall security posture.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.intuneRestrictUserDeviceJoin.disableUserDeviceJoin","label":"Disable users from joining devices","defaultValue":true}
        IMPACT
            High Impact
        ADDEDDATE
            2026-05-15
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
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the intuneRestrictUserDeviceJoin state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }
    # Current M365 Config
    $CurrentOdataType = $PreviousSetting.azureADJoin.allowedToJoin.'@odata.type'
    $IsAdminConfigurable = [bool]$PreviousSetting.azureADJoin.isAdminConfigurable

    # Standards Config
    $DisableUserDeviceJoin = [bool]$Settings.disableUserDeviceJoin

    # State comparison
    $DesiredOdataType = if ($DisableUserDeviceJoin) { '#microsoft.graph.noDeviceRegistrationMembership' } else { '#microsoft.graph.allDeviceRegistrationMembership' }
    $CurrentDisableUserDeviceJoin = ($CurrentOdataType -eq '#microsoft.graph.noDeviceRegistrationMembership')
    $StateIsCorrect = ($CurrentOdataType -eq $DesiredOdataType)
    $DesiredStateText = if ($DisableUserDeviceJoin) { 'disabled' } else { 'enabled' }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Device join restriction is already configured (users allowed to join: $DesiredStateText)." -sev Info
        } elseif ($IsAdminConfigurable -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Cannot remediate device join restriction: azureADJoin.isAdminConfigurable is false for this tenant. Skipping remediation.' -sev Warn
        } else {
            try {
                $PreviousSetting.azureADJoin.allowedToJoin = @{ '@odata.type' = $DesiredOdataType; users = $null; groups = $null }
                $NewBody = ConvertTo-Json -Compress -InputObject $PreviousSetting -Depth 10
                New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
                $CurrentOdataType = $DesiredOdataType
                $CurrentDisableUserDeviceJoin = ($CurrentOdataType -eq '#microsoft.graph.noDeviceRegistrationMembership')
                $StateIsCorrect = ($CurrentOdataType -eq $DesiredOdataType)
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set device join restriction (users allowed to join: $DesiredStateText)." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set device join restriction (users allowed to join: $DesiredStateText). Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Device join restriction is configured as expected (users allowed to join: $DesiredStateText)." -sev Info
        } else {
            Write-StandardsAlert -message "Device join restriction is not configured as expected (users allowed to join: $DesiredStateText)" -object @{ current = @{ disableUserDeviceJoin = $CurrentDisableUserDeviceJoin }; desired = @{ disableUserDeviceJoin = $DisableUserDeviceJoin } } -tenant $Tenant -standardName 'intuneRestrictUserDeviceJoin' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Device join restriction is not configured as expected (users allowed to join: $DesiredStateText)." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            disableUserDeviceJoin = $CurrentDisableUserDeviceJoin
        }
        $ExpectedValue = @{
            disableUserDeviceJoin = $DisableUserDeviceJoin
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.intuneRestrictUserDeviceJoin' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'intuneRestrictUserDeviceJoin' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
