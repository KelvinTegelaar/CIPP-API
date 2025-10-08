function Invoke-ExecMailboxRestore {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    Param($Request, $TriggerMetadata)
    try {
        $Action = $Request.Query.Action ?? $Request.Body.Action
        $Identity = $Request.Query.Identity ?? $Request.Body.Identity
        $TenantFilter = $Request.Query.TenantFilter ?? $Request.Body.TenantFilter

        switch ($Action) {
            'Remove' {
                $ExoRequest = @{
                    tenantid  = $TenantFilter
                    cmdlet    = 'Remove-MailboxRestoreRequest'
                    cmdParams = @{
                        Identity = $Identity
                    }
                }
                $SuccessMessage = 'Mailbox restore request removed successfully'
            }
            'Resume' {
                $ExoRequest = @{
                    tenantid  = $TenantFilter
                    cmdlet    = 'Resume-MailboxRestoreRequest'
                    cmdParams = @{
                        Identity = $Identity
                    }
                }
                $SuccessMessage = 'Mailbox restore request resumed successfully'
            }
            'Suspend' {
                $ExoRequest = @{
                    tenantid  = $TenantFilter
                    cmdlet    = 'Suspend-MailboxRestoreRequest'
                    cmdParams = @{
                        Identity = $Identity
                    }
                }
                $SuccessMessage = 'Mailbox restore request suspended successfully'
            }
            default {
                $RequestName = $Request.Body.RequestName
                $SourceMailbox = $Request.Body.SourceMailbox.value ?? $Request.Body.SourceMailbox
                $TargetMailbox = $Request.Body.TargetMailbox.value ?? $Request.Body.TargetMailbox

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
                if ($Request.Body.AssociatedMessagesCopyOption) {
                    $ExoRequest.cmdParams.AssociatedMessagesCopyOption = $Request.Body.AssociatedMessagesCopyOption.value
                }
                if ($Request.Body.ExcludeFolders) {
                    $ExoRequest.cmdParams.ExcludeFolders = $Request.Body.ExcludeFolders.value
                }
                if ($Request.Body.IncludeFolders) {
                    $ExoRequest.cmdParams.IncludeFolders = $Request.Body.IncludeFolders.value
                }
                if ($Request.Body.BatchName) {
                    $ExoRequest.cmdParams.BatchName = $Request.Body.BatchName
                }
                if ($Request.Body.CompletedRequestAgeLimit) {
                    $ExoRequest.cmdParams.CompletedRequestAgeLimit = $Request.Body.CompletedRequestAgeLimit
                }
                if ($Request.Body.ConflictResolutionOption) {
                    $ExoRequest.cmdParams.ConflictResolutionOption = $Request.Body.ConflictResolutionOption.value
                }
                if ($Request.Body.SourceRootFolder) {
                    $ExoRequest.cmdParams.SourceRootFolder = $Request.Body.SourceRootFolder
                }
                if ($Request.Body.TargetRootFolder) {
                    $ExoRequest.cmdParams.TargetRootFolder = $Request.Body.TargetRootFolder
                }
                if ($Request.Body.TargetType) {
                    $ExoRequest.cmdParams.TargetType = $Request.Body.TargetType.value
                }
                if ([int]$Request.Body.BadItemLimit -gt 0) {
                    $ExoRequest.cmdParams.BadItemLimit = $Request.Body.BadItemLimit
                }
                if ([int]$Request.Body.LargeItemLimit -gt 0) {
                    $ExoRequest.cmdParams.LargeItemLimit = $Request.Body.LargeItemLimit
                }
                if ($Request.Body.ExcludeDumpster) {
                    $ExoRequest.cmdParams.ExcludeDumpster = $Request.Body.ExcludeDumpster
                }
                if ($Request.Body.SourceIsArchive) {
                    $ExoRequest.cmdParams.SourceIsArchive = $Request.Body.SourceIsArchive
                }
                if ($Request.Body.TargetIsArchive) {
                    $ExoRequest.cmdParams.TargetIsArchive = $Request.Body.TargetIsArchive
                }

                Write-Information ($ExoRequest | ConvertTo-Json)
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
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
