function Invoke-ListMailboxForwarding {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter
    $UseReportDB = $Request.Query.UseReportDB

    try {
        # If UseReportDB is specified, retrieve from report database
        if ($UseReportDB -eq 'true') {
            try {
                $GraphRequest = Get-CIPPMailboxForwardingReport -TenantFilter $TenantFilter
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

        # Live query from Exchange Online
        $Select = 'UserPrincipalName,DisplayName,PrimarySMTPAddress,RecipientTypeDetails,ForwardingSmtpAddress,DeliverToMailboxAndForward,ForwardingAddress'
        $ExoRequest = @{
            tenantid  = $TenantFilter
            cmdlet    = 'Get-Mailbox'
            cmdParams = @{}
            Select    = $Select
        }

        $Mailboxes = New-ExoRequest @ExoRequest

        $GraphRequest = foreach ($Mailbox in $Mailboxes) {
            $HasExternalForwarding = -not [string]::IsNullOrWhiteSpace($Mailbox.ForwardingSmtpAddress)
            $HasInternalForwarding = -not [string]::IsNullOrWhiteSpace($Mailbox.ForwardingAddress)
            $HasAnyForwarding = $HasExternalForwarding -or $HasInternalForwarding

            # Only include mailboxes with forwarding configured
            if (-not $HasAnyForwarding) {
                continue
            }

            $ForwardingType = if ($HasExternalForwarding -and $HasInternalForwarding) {
                'Both'
            } elseif ($HasExternalForwarding) {
                'External'
            } else {
                'Internal'
            }

            $ForwardTo = if ($HasExternalForwarding -and $HasInternalForwarding) {
                "$($Mailbox.ForwardingSmtpAddress -replace 'smtp:', ''), $($Mailbox.ForwardingAddress)"
            } elseif ($HasExternalForwarding) {
                $Mailbox.ForwardingSmtpAddress -replace 'smtp:', ''
            } else {
                $Mailbox.ForwardingAddress
            }

            [PSCustomObject]@{
                UPN                        = $Mailbox.UserPrincipalName
                DisplayName                = $Mailbox.DisplayName
                PrimarySmtpAddress         = $Mailbox.PrimarySMTPAddress
                RecipientTypeDetails       = $Mailbox.RecipientTypeDetails
                ForwardingType             = $ForwardingType
                ForwardTo                  = $ForwardTo
                ForwardingSmtpAddress      = $Mailbox.ForwardingSmtpAddress -replace 'smtp:', ''
                InternalForwardingAddress  = $Mailbox.ForwardingAddress
                DeliverToMailboxAndForward = $Mailbox.DeliverToMailboxAndForward
            }
        }

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Mailbox forwarding listed for $($TenantFilter)" -sev Debug
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
