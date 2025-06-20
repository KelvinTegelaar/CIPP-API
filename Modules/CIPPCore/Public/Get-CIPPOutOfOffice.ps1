function Get-CIPPOutOfOffice {
    [CmdletBinding()]
    param (
        $UserID,
        $TenantFilter,
        $APIName = 'Get Out of Office',
        $Headers
    )

    try {
        $OutOfOffice = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxAutoReplyConfiguration' -cmdParams @{Identity = $UserID } -Anchor $UserID
        $Results = @{
            AutoReplyState  = $OutOfOffice.AutoReplyState
            StartTime       = $OutOfOffice.StartTime.ToString('yyyy-MM-dd HH:mm')
            EndTime         = $OutOfOffice.EndTime.ToString('yyyy-MM-dd HH:mm')
            InternalMessage = $OutOfOffice.InternalMessage
            ExternalMessage = $OutOfOffice.ExternalMessage
        } | ConvertTo-Json
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not retrieve out of office message for $($UserID). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
        throw $Results
    }
}
