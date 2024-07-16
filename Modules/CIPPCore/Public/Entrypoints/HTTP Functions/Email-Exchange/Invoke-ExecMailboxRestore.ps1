function Invoke-ExecMailboxRestore {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    Param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        switch ($Request.Query.Action) {
            'Remove' {
                $ExoRequest = @{
                    tenantid  = $Request.Query.TenantFilter
                    cmdlet    = 'Remove-MailboxRestoreRequest'
                    cmdParams = @{
                        Identity = $Request.Query.Identity
                    }
                }
                $SuccessMessage = 'Mailbox restore request removed successfully'
            }
            'Resume' {
                $ExoRequest = @{
                    tenantid  = $Request.Query.TenantFilter
                    cmdlet    = 'Resume-MailboxRestoreRequest'
                    cmdParams = @{
                        Identity = $Request.Query.Identity
                    }
                }
                $SuccessMessage = 'Mailbox restore request resumed successfully'
            }
            'Suspend' {
                $ExoRequest = @{
                    tenantid  = $Request.Query.TenantFilter
                    cmdlet    = 'Suspend-MailboxRestoreRequest'
                    cmdParams = @{
                        Identity = $Request.Query.Identity
                    }
                }
                $SuccessMessage = 'Mailbox restore request suspended successfully'
            }
            default {
                $TenantFilter = $Request.Body.TenantFilter
                $RequestName = $Request.Body.RequestName
                $SourceMailbox = $Request.Body.SourceMailbox
                $TargetMailbox = if (!$Request.Body.input) {$Request.Body.TargetMailbox} else {$Request.Body.input}

                $ExoRequest = @{
                    tenantid  = $TenantFilter
                    cmdlet    = 'New-MailboxRestoreRequest'
                    cmdParams = @{
                        Name                  = $RequestName
                        SourceMailbox         = $SourceMailbox
                        TargetMailbox         = $TargetMailbox
                        AllowLegacyDNMismatch = $true
                    }
                }
                if ([bool]$Request.Body.AcceptLargeDataLoss -eq $true) {
                    $ExoRequest.cmdParams.AcceptLargeDataLoss = $true
                }
                if ([int]$Request.Body.BadItemLimit -gt 0) {
                    $ExoRequest.cmdParams.BadItemLimit = $Request.Body.BadItemLimit
                }
                if ([int]$Request.Body.LargeItemLimit -gt 0) {
                    $ExoRequest.cmdParams.LargeItemLimit = $Request.Body.LargeItemLimit
                }

                $SuccessMessage = 'Mailbox restore request created successfully'
            }
        }

        $GraphRequest = New-ExoRequest @ExoRequest

        $Body = @{
            RestoreRequest = $GraphRequest
            Results        = @($SuccessMessage)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::OK
        $Body = @{
            RestoreRequest = $null
            Results        = @($ErrorMessage)
            colour         = 'danger'
        }
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}