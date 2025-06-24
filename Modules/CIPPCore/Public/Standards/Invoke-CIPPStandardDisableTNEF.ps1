function Invoke-CIPPStandardDisableTNEF {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableTNEF
    .SYNOPSIS
        (Label) Disable TNEF/winmail.dat
    .DESCRIPTION
        (Helptext) Disables Transport Neutral Encapsulation Format (TNEF)/winmail.dat for the tenant. TNEF can cause issues if the recipient is not using a client supporting TNEF.
        (DocsDescription) Disables Transport Neutral Encapsulation Format (TNEF)/winmail.dat for the tenant. TNEF can cause issues if the recipient is not using a client supporting TNEF. Cannot be overridden by the user. For more information, see [Microsoft's documentation.](https://learn.microsoft.com/en-us/exchange/mail-flow/content-conversion/tnef-conversion?view=exchserver-2019)
    .NOTES
        CAT
            Exchange Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-04-26
        POWERSHELLEQUIVALENT
            Set-RemoteDomain -Identity 'Default' -TNEFEnabled \$false
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param ($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableTNEF'

    $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-RemoteDomain' -cmdParams @{Identity = 'Default' }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CurrentState.TNEFEnabled -ne $false) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-RemoteDomain' -cmdParams @{Identity = 'Default'; TNEFEnabled = $false } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled TNEF for Default Remote Domain' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable TNEF for Default Remote Domain. Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'TNEF is already disabled for Default Remote Domain' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentState.TNEFEnabled -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'TNEF is disabled for Default Remote Domain' -sev Info
        } else {
            $Object = $CurrentState | Select-Object -Property TNEFEnabled
            Write-StandardsAlert -message 'TNEF is not disabled for Default Remote Domain' -object $Object -tenant $tenant -standardName 'DisableTNEF' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'TNEF is not disabled for Default Remote Domain' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $State = if ($CurrentState.TNEFEnabled -ne $false) { $false } else { $true }
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableTNEF' -FieldValue $State -Tenant $tenant
        Add-CIPPBPAField -FieldName 'TNEFDisabled' -FieldValue $State -StoreAs bool -Tenant $tenant
    }

}
