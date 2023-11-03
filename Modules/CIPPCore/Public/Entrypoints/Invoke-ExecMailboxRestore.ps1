function Invoke-ExecMailboxRestore {
    Param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.TenantFilter
    $RequestName = $Request.Body.RequestName
    $SourceMailbox = $Request.Body.SourceMailbox
    $TargetMailbox = $Request.Body.TargetMailbox

    try {
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

        $GraphRequest = New-ExoRequest @ExoRequest

        $Body = @{
            RestoreRequest = $GraphRequest
            Results        = @('Mailbox restore request started successfully')
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Body = @{
            RestoreRequest = $null
            Results        = @($ErrorMessage)
        }
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}