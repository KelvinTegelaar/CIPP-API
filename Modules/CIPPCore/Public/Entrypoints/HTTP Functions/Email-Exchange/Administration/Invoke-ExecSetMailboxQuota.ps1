using namespace System.Net

function Invoke-ExecSetMailboxQuota {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Username = $Request.Body.user
    $TenantFilter = $Request.Body.tenantFilter
    $Quota = $Request.Body.quota
    $Results = try {
        if ($Request.Body.ProhibitSendQuota) {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $Username; ProhibitSendQuota = $Quota }
            "Changed ProhibitSendQuota for $Username - $($Quota)"
            Write-LogMessage -headers $Headers -API $APIName -message "Changed ProhibitSendQuota for $Username - $($Quota)" -Sev 'Info' -tenant $TenantFilter
        }
        if ($Request.Body.ProhibitSendReceiveQuota) {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $Username; ProhibitSendReceiveQuota = $Quota }
            "Changed ProhibitSendReceiveQuota for $Username - $($Quota)"
            Write-LogMessage -headers $Headers -API $APIName -message "Changed ProhibitSendReceiveQuota for $Username - $($Quota)" -Sev 'Info' -tenant $TenantFilter
        }
        if ($Request.Body.IssueWarningQuota) {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $Username; IssueWarningQuota = $Quota }
            "Changed IssueWarningQuota for $Username - $($Quota)"
            Write-LogMessage -headers $Headers -API $APIName -message "Changed IssueWarningQuota for $Username - $($Quota)" -Sev 'Info' -tenant $TenantFilter
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Could not adjust mailbox quota for $($Username)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $Results = "Could not adjust mailbox quota for $($Username). Error: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    }
}
