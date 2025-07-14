function Invoke-CIPPStandardSendReceiveLimitTenant {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SendReceiveLimitTenant
    .SYNOPSIS
        (Label) Set send/receive size limits
    .DESCRIPTION
        (Helptext) Sets the Send and Receive limits for new users. Valid values are 1MB to 150MB
        (DocsDescription) Sets the Send and Receive limits for new users. Valid values are 1MB to 150MB
    .NOTES
        CAT
            Exchange Standards
        TAG
        ADDEDCOMPONENT
            {"type":"number","name":"standards.SendReceiveLimitTenant.SendLimit","label":"Send limit in MB (Default is 35)","defaultValue":35}
            {"type":"number","name":"standards.SendReceiveLimitTenant.ReceiveLimit","label":"Receive Limit in MB (Default is 36)","defaultValue":36}
        IMPACT
            Low Impact
        ADDEDDATE
            2023-11-16
        POWERSHELLEQUIVALENT
            Set-MailboxPlan
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    # Input validation
    if ([Int32]$Settings.SendLimit -lt 1 -or [Int32]$Settings.SendLimit -gt 150) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'SendReceiveLimitTenant: Invalid SendLimit parameter set' -sev Error
        return
    }

    if ([Int32]$Settings.ReceiveLimit -lt 1 -or [Int32]$Settings.ReceiveLimit -gt 150) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'SendReceiveLimitTenant: Invalid ReceiveLimit parameter set' -sev Error
        return
    }

    $AllMailBoxPlans = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxPlan' | Select-Object DisplayName, MaxSendSize, MaxReceiveSize, GUID
    $MaxSendSize = "$($Settings.SendLimit)MB"
    $MaxReceiveSize = "$($Settings.ReceiveLimit)MB"
    $MaxSendSizeBytes = $Settings.SendLimit * 1MB
    $MaxReceiveSizeBytes = $Settings.ReceiveLimit * 1MB

    $NotSetCorrectly = foreach ($MailboxPlan in $AllMailBoxPlans) {
        if ($MailboxPlan.MaxSendSize -eq 'Unlimited') {
            $PlanMaxSendSize = [int64]::MaxValue
        } else {
            $PlanMaxSendSize = [int64]($MailboxPlan.MaxSendSize -replace '.*\(([\d,]+).*', '$1' -replace ',', '')
        }

        if ($MailboxPlan.MaxReceiveSize -eq 'Unlimited') {
            $PlanMaxReceiveSize = [int64]::MaxValue
        } else {
            $PlanMaxReceiveSize = [int64]($MailboxPlan.MaxReceiveSize -replace '.*\(([\d,]+).*', '$1' -replace ',', '')
        }

        if ($PlanMaxSendSize -ne $MaxSendSizeBytes -or $PlanMaxReceiveSize -ne $MaxReceiveSizeBytes) {
            $MailboxPlan
        }
    }

    if ($Settings.remediate -eq $true) {
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
            Write-StandardsAlert -message "The tenant send($($Settings.SendLimit)MB) and receive($($Settings.ReceiveLimit)MB) limits are not set correctly" -object $NotSetCorrectly -tenant $tenant -standardName 'SendReceiveLimitTenant' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant send($($Settings.SendLimit)MB) and receive($($Settings.ReceiveLimit)MB) limits are not set correctly" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SendReceiveLimit' -FieldValue $NotSetCorrectly -StoreAs json -Tenant $tenant

        if ($NotSetCorrectly.Count -eq 0) {
            $FieldValue = $true
        } else {
            $FieldValue = $NotSetCorrectly
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SendReceiveLimitTenant' -FieldValue $FieldValue -Tenant $tenant
    }
}
