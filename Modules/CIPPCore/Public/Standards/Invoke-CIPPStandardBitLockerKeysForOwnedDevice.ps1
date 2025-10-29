function Invoke-CIPPStandardBitLockerKeysForOwnedDevice {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) BitLockerKeysForOwnedDevice
    .SYNOPSIS
        (Label) Restrict users from recovering BitLocker keys for owned devices
    .DESCRIPTION
    (Helptext) Controls whether standard users can recover BitLocker keys for devices they own via Microsoft 365 portals.
    (DocsDescription) Updates the default user role setting that governs access to BitLocker recovery keys for owned devices. This allows administrators to either permit self-service recovery or require helpdesk involvement through Microsoft Entra authorization policies.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "NIST CSF 2.0 (PR.AA-05)"
        EXECUTIVETEXT
            Ensures administrators retain control over BitLocker recovery secrets when required, while still allowing flexibility to enable self-service recovery when business needs demand it.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select state","name":"standards.BitLockerKeysForOwnedDevice.state","options":[{"label":"Restrict","value":"restrict"},{"label":"Allow","value":"allow"}]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-10-12
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthorizationPolicy
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'BitLockerKeysForOwnedDevice'

    $StateValue = $Settings.state.value ?? $Settings.state
    if ([string]::IsNullOrWhiteSpace($StateValue)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'BitLockerKeysForOwnedDevice: Invalid state parameter set.' -sev Error
        return
    }

    switch ($StateValue.ToLowerInvariant()) {
        'restrict' { $DesiredValue = $false; $DesiredLabel = 'restricted'; break }
        'allow' { $DesiredValue = $true; $DesiredLabel = 'allowed'; break }
        default {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "BitLockerKeysForOwnedDevice: Unsupported state value '$StateValue'." -sev Error
            return
        }
    }

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the BitLockerKeysForOwnedDevice state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }
    $CurrentValue = [bool]$CurrentState.defaultUserRolePermissions.allowedToReadBitLockerKeysForOwnedDevice
    $StateIsCorrect = ($CurrentValue -eq $DesiredValue)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Users are already $DesiredLabel from recovering BitLocker keys for their owned devices." -sev Info
        } else {
            try {
                $BodyObject = @{ defaultUserRolePermissions = @{ allowedToReadBitLockerKeysForOwnedDevice = $DesiredValue } }
                $BodyJson = $BodyObject | ConvertTo-Json -Depth 4 -Compress
                $null = New-GraphPOSTRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type patch -Body $BodyJson
                $ActionMessage = if ($DesiredValue) { 'Allowed users to recover BitLocker keys for their owned devices.' } else { 'Restricted users from recovering BitLocker keys for their owned devices.' }
                Write-LogMessage -API 'Standards' -tenant $tenant -message $ActionMessage -sev Info


                # Update current state variables to reflect the change immediately if running remediate and report/alert together
                $CurrentState.defaultUserRolePermissions.allowedToReadBitLockerKeysForOwnedDevice = $DesiredValue
                $CurrentValue = $DesiredValue
                $StateIsCorrect = $true
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to $StateValue users to recover BitLocker keys for their owned devices: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Users are $DesiredLabel to recover BitLocker keys for their owned devices as configured." -sev Info
        } else {
            $CurrentLabel = if ($CurrentValue) { 'allowed' } else { 'restricted' }
            $AlertMessage = "Users are $CurrentLabel to recover BitLocker keys for their owned devices but should be $DesiredLabel."
            Write-StandardsAlert -message $AlertMessage -object $CurrentState -tenant $tenant -standardName 'BitLockerKeysForOwnedDevice' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message $AlertMessage -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.BitLockerKeysForOwnedDevice' -FieldValue $StateIsCorrect -Tenant $tenant
        Add-CIPPBPAField -FieldName 'BitLockerKeysForOwnedDevice' -FieldValue $CurrentValue -StoreAs bool -Tenant $tenant
    }
}
