function Invoke-CIPPStandardSendReceiveLimitTenant {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $AllMailBoxPlans = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxPlan' | Select-Object DisplayName, MaxSendSize, MaxReceiveSize, GUID
    If ($Settings.remediate) {
        Write-Host "Time to remediate. Our Settings are $($Settings.SendLimit)MB and $($Settings.ReceiveLimit)MB"
        $MaxReceiveSize = [int64]"$($Settings.SendLimit)MB"
        $MaxSendSize = [int64]"$($Settings.ReceiveLimit)MB"

        try {
            foreach ($MailboxPlan in $AllMailBoxPlans) {
                if ($MailboxPlan.MaxSendSize -ne $MaxSendSize -and $MailboxPlan.MaxReceiveSize -ne $MaxReceiveSize) {
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxPlan' -cmdParams @{Identity = $MailboxPlan.GUID; MaxSendSize = $MaxSendSize; MaxReceiveSize = $MaxReceiveSize } -useSystemMailbox $true 
                }
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Successfully set the tenant send and receive limits ' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set the tenant send and receive limits. Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        foreach ($MailboxPlan in $AllMailBoxPlans) {
            if ($MailboxPlan.MaxSendSize -ne $MaxSendSize -and $MailboxPlan.MaxReceiveSize -ne $MaxReceiveSize) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant send and receive limits are not set correctly for $($MailboxPlan.DisplayName)" -sev Alert
            }
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'SendReceiveLimit' -FieldValue $AllMailBoxPlans -StoreAs json -Tenant $tenant
    }
}
