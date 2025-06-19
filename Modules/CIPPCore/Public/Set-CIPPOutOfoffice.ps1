function Set-CIPPOutOfOffice {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserID,
        $InternalMessage,
        $ExternalMessage,
        $TenantFilter,
        [ValidateSet('Enabled', 'Disabled', 'Scheduled')]
        [Parameter(Mandatory = $true)]
        [string]$State,
        $APIName = 'Set Out of Office',
        $Headers,
        $StartTime,
        $EndTime
    )

    try {
        if (-not $StartTime) {
            $StartTime = (Get-Date).ToString()
        }
        if (-not $EndTime) {
            $EndTime = (Get-Date $StartTime).AddDays(7)
        }
        $CmdParams = @{
            Identity       = $UserID
            AutoReplyState = $State
        }

        if (-not [string]::IsNullOrWhiteSpace($InternalMessage)) {
            $CmdParams.InternalMessage = $InternalMessage
        }

        if (-not [string]::IsNullOrWhiteSpace($ExternalMessage)) {
            $CmdParams.ExternalMessage = $ExternalMessage
        }

        if ($State -eq 'Scheduled') {
            $CmdParams.StartTime = $StartTime
            $CmdParams.EndTime = $EndTime
        }

        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxAutoReplyConfiguration' -cmdParams $CmdParams -Anchor $UserID

        if ($State -eq 'Scheduled') {
            $Results = "Scheduled Out-of-office for $($UserID) between $($StartTime.toString()) and $($EndTime.toString())"
            Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Info' -tenant $TenantFilter
        } else {
            $Results = "Set Out-of-office for $($UserID) to $State."
            Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Info' -tenant $TenantFilter
        }
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not add OOO for $($UserID). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Results
    }
}
