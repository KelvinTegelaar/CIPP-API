function Invoke-CIPPStandardSendReceiveLimitTenant {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $AllMailBoxPlans = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxPlan' | Select-Object DisplayName, MaxSendSize, MaxReceiveSize, GUID
    If ($Settings.Remediate) {
        $Limits = $Settings.SendReceiveLimit
        if ($Limits[0] -like '*MB*') {
            $MaxSendSize = [int]($Limits[0] -Replace '[a-zA-Z]', '') * 1MB
        } elseif ($Limits[0] -like '*KB*') {
            $MaxSendSize = [int]($Limits[0] -Replace '[a-zA-Z]', '') * 1KB
        } # Default to 35MB if invalid input
        else {
            $MaxSendSize = 35MB
        }
        if ($MaxSendSize -gt 150MB) {
            $MaxSendSize = 150MB
        }
        if ($Limits[1] -like '*MB*') {
            $MaxReceiveSize = [int]($Limits[1] -Replace '[a-zA-Z]', '') * 1MB
        } elseif ($Limits[1] -like '*KB*') {
            $MaxReceiveSize = [int]($Limits[1] -Replace '[a-zA-Z]', '') * 1KB
        } else {
            $MaxReceiveSize = 36MB
        } 

        if ($MaxReceiveSize -gt 150MB) {
            $MaxReceiveSize = 150MB
        }

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
    if ($Settings.Alert) {
        foreach ($MailboxPlan in $AllMailBoxPlans) {
            if ($MailboxPlan.MaxSendSize -ne $MaxSendSize -and $MailboxPlan.MaxReceiveSize -ne $MaxReceiveSize) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "The tenant send and receive limits are not set correctly for $($MailboxPlan.DisplayName)" -sev Alert
            }
        }
    }
    if ($Settings.Report) {
        Add-CIPPBPAField -FieldName 'SendReceiveLimit' -FieldValue $AllMailBoxPlans -StoreAs json -Tenant $tenant
    }
}
