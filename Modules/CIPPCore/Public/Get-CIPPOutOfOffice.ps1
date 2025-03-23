function Get-CIPPOutOfOffice {
    [CmdletBinding()]
    param (
        $userid,
        $TenantFilter,
        $APIName = 'Get Out of Office',
        $Headers
    )

    try {
        $OutOfOffice = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxAutoReplyConfiguration' -cmdParams @{Identity = $userid } -Anchor $userid
        $Results = @{
            AutoReplyState  = $OutOfOffice.AutoReplyState
            StartTime       = $OutOfOffice.StartTime.ToString('yyyy-MM-dd HH:mm')
            EndTime         = $OutOfOffice.EndTime.ToString('yyyy-MM-dd HH:mm')
            InternalMessage = $OutOfOffice.InternalMessage
            ExternalMessage = $OutOfOffice.ExternalMessage
        } | ConvertTo-Json
        return $Results
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        return "Could not retrieve out of office message for $($userid). Error: $ErrorMessage"
    }
}
