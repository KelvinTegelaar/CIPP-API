function Invoke-CIPPStandardSendReceiveLimitTenant {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    SendReceiveLimitTenant
    .CAT
    Exchange Standards
    .TAG
    "lowimpact"
    .HELPTEXT
    Sets the Send and Receive limits for new users. Valid values are 1MB to 150MB
    .ADDEDCOMPONENT
    {"type":"number","name":"standards.SendReceiveLimitTenant.SendLimit","label":"Send limit in MB (Default is 35)","default":35}
    {"type":"number","name":"standards.SendReceiveLimitTenant.ReceiveLimit","label":"Receive Limit in MB (Default is 36)","default":36}
    .LABEL
    Set send/receive size limits
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Set-MailboxPlan
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Sets the Send and Receive limits for new users. Valid values are 1MB to 150MB
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)

    # Input validation
    if ($Settings.SendLimit -lt 1 -or $Settings.SendLimit -gt 150) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'SendReceiveLimitTenant: Invalid SendLimit parameter set' -sev Error
        Return
    }

    # Input validation
    if ($Settings.ReceiveLimit -lt 1 -or $Settings.ReceiveLimit -gt 150) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'SendReceiveLimitTenant: Invalid ReceiveLimit parameter set' -sev Error
        Return
    }


    $AllMailBoxPlans = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxPlan' | Select-Object DisplayName, MaxSendSize, MaxReceiveSize, GUID
    $MaxSendSize = [int64]"$($Settings.SendLimit)MB"
    $MaxReceiveSize = [int64]"$($Settings.ReceiveLimit)MB"

    $NotSetCorrectly = foreach ($MailboxPlan in $AllMailBoxPlans) {
        $PlanMaxSendSize = [int64]($MailboxPlan.MaxSendSize -replace '.*\(([\d,]+).*', '$1' -replace ',', '')
        $PlanMaxReceiveSize = [int64]($MailboxPlan.MaxReceiveSize -replace '.*\(([\d,]+).*', '$1' -replace ',', '')
        if ($PlanMaxSendSize -ne $MaxSendSize -or $PlanMaxReceiveSize -ne $MaxReceiveSize) {
            $MailboxPlan
        }
    }

    If ($Settings.remediate -eq $true) {
        Write-Host "Time to remediate. Our Settings are $($Settings.SendLimit)MB and $($Settings.ReceiveLimit)MB"

        if ($NotSetCorrectly.Count -gt 0) {
            Write-Host "Found $($NotSetCorrectly.Count) Mailbox Plans that are not set correctly. Setting them to $($Settings.SendLimit)MB and $($Settings.ReceiveLimit)MB"
            try {
                foreach ($MailboxPlan in $NotSetCorrectly) {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxPlan' -cmdParams @{Identity = $MailboxPlan.GUID; MaxSendSize = $MaxSendSize; MaxReceiveSize = $MaxReceiveSize } -useSystemMailbox $true
                }
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully set the tenant send($($Settings.SendLimit)MB) and receive($($Settings.ReceiveLimit)MB) limits" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set the tenant send and receive limits. Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant send($($Settings.SendLimit)MB) and receive($($Settings.ReceiveLimit)MB) limits are already set correctly" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {

        if ($NotSetCorrectly.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant send($($Settings.SendLimit)MB) and receive($($Settings.ReceiveLimit)MB) limits are set correctly" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant send($($Settings.SendLimit)MB) and receive($($Settings.ReceiveLimit)MB) limits are not set correctly" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SendReceiveLimit' -FieldValue $NotSetCorrectly -StoreAs json -Tenant $tenant
    }
}




