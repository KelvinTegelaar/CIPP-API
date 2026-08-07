function Invoke-ListMailboxForwarding {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists mailbox forwarding rules and configurations for a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    try {
        # If UseReportDB is specified, retrieve from report database
        if ($UseReportDB) {
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

            # External takes precedence when both are configured
            $ForwardingType = if ($HasExternalForwarding) {
                'External'
            } else {
                'Internal'
            }

            # External takes precedence when both are configured
            $ForwardTo = if ($HasExternalForwarding) {
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
