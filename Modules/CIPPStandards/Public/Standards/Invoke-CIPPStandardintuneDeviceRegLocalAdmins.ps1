function Invoke-CIPPStandardintuneDeviceRegLocalAdmins {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) intuneDeviceRegLocalAdmins
    .SYNOPSIS
        (Label) Configure local administrator rights for users joining devices
    .DESCRIPTION
        (Helptext) Controls whether users who register Microsoft Entra joined devices are granted local administrator rights on those devices and if Global Administrators are added as local admins.
        (DocsDescription) Configures the Device Registration Policy local administrator behavior for registering users. When enabled, users who register devices are not granted local administrator rights, you can also configure if Global Administrators are added as local admins.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Controls whether employees who enroll devices automatically receive local administrator access. Disabling registering-user admin rights follows least-privilege principles and reduces security risk from over-privileged endpoints.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.intuneDeviceRegLocalAdmins.disableRegisteringUsers","label":"Disable registering users as local administrators","defaultValue":true}
            {"type":"switch","name":"standards.intuneDeviceRegLocalAdmins.enableGlobalAdmins","label":"Allow Global Administrators to be local administrators","defaultValue":true}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-02-23
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
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the intuneDeviceRegLocalAdmins state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }
    # Current M365 Config
    $CurrentOdataType = $PreviousSetting.azureADJoin.localAdmins.registeringUsers.'@odata.type'
    $CurrentEnableGlobalAdmins = [bool]$PreviousSetting.azureADJoin.localAdmins.enableGlobalAdmins

    # Standards Config
    $DisableRegisteringUsers = [bool]$Settings.disableRegisteringUsers
    $EnableGlobalAdmins = [bool]$Settings.enableGlobalAdmins

    # State comparison
    $DesiredOdataType = if ($DisableRegisteringUsers) { '#microsoft.graph.noDeviceRegistrationMembership' } else { '#microsoft.graph.allDeviceRegistrationMembership' }
    $StateIsCorrect = ($CurrentOdataType -eq $DesiredOdataType) -and ($CurrentEnableGlobalAdmins -eq $EnableGlobalAdmins)
    $DesiredStateText = if ($DisableRegisteringUsers) { 'disabled' } else { 'enabled' }
    $DesiredGlobalAdminsText = if ($EnableGlobalAdmins) { 'enabled' } else { 'disabled' }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Local administrator settings are already configured (registering users: $DesiredStateText, global admins: $DesiredGlobalAdminsText)." -sev Info
        } else {
            try {
                $PreviousSetting.azureADJoin.localAdmins.registeringUsers = @{ '@odata.type' = $DesiredOdataType }
                $PreviousSetting.azureADJoin.localAdmins.enableGlobalAdmins = $EnableGlobalAdmins
                $NewBody = ConvertTo-Json -Compress -InputObject $PreviousSetting -Depth 10
                New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
                $CurrentOdataType = $DesiredOdataType
                $CurrentEnableGlobalAdmins = $EnableGlobalAdmins
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set local administrator settings (registering users: $DesiredStateText, global admins: $DesiredGlobalAdminsText)." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set local administrator settings (registering users: $DesiredStateText, global admins: $DesiredGlobalAdminsText). Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Local administrator settings are configured as expected (registering users: $DesiredStateText, global admins: $DesiredGlobalAdminsText)." -sev Info
        } else {
            Write-StandardsAlert -message "Local administrator settings are not configured as expected (registering users: $DesiredStateText, global admins: $DesiredGlobalAdminsText)" -object @{ current = @{ registeringUsers = $CurrentOdataType; enableGlobalAdmins = $CurrentEnableGlobalAdmins }; desired = @{ registeringUsers = $DesiredOdataType; enableGlobalAdmins = $EnableGlobalAdmins } } -tenant $Tenant -standardName 'intuneDeviceRegLocalAdmins' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Local administrator settings are not configured as expected (registering users: $DesiredStateText, global admins: $DesiredGlobalAdminsText)." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            registeringUsers = @{
                '@odata.type' = $CurrentOdataType
            }
            enableGlobalAdmins = $CurrentEnableGlobalAdmins
        }
        $ExpectedValue = @{
            registeringUsers = @{
                '@odata.type' = $DesiredOdataType
            }
            enableGlobalAdmins = $EnableGlobalAdmins
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.intuneDeviceRegLocalAdmins' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'intuneDeviceRegLocalAdmins' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
