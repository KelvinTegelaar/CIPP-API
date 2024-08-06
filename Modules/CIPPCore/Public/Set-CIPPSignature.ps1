function Set-CIPPSignature {
    [CmdletBinding()]
    param (
        $userid,
        $InternalMessage,
        $ExternalMessage,
        $TenantFilter,
        $State,
        $APIName = 'Set Outlook Roaming Signature',
        $ExecutingUser,
        $StartTime,
        $EndTime
    )

    try {
        $SignatureProfile = @'
[{"name":"Roaming_New_Signature","itemClass":"","id":"","scope":"AdeleV@M365x42953883.OnMicrosoft.com","parentSetting":"","secondaryKey":"","type":"String","timestamp":638296273181532792,"metadata":"","value":"Kelvin","isFirstSync":"true","source":"UserOverride"}]
'@
        $null = New-GraphPostRequest -uri 'https://substrate.office.com/ows/beta/outlookcloudsettings/settings/global' -tenantid $TenantFilter -type PATCH -contentType 'application/json' -verbose -scope 'https://outlook.office.com/.default'
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Set Out-of-office for $($userid) to $state" -Sev 'Info' -tenant $TenantFilter
        return "Set Out-of-office for $($userid) to $state."

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add OOO for $($userid). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not add out of office message for $($userid). Error: $($ErrorMessage.NormalizedError)"
    }
}
