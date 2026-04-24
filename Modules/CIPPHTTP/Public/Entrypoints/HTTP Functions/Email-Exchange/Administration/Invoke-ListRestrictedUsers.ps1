function Invoke-ListRestrictedUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists users from the restricted senders list in Exchange Online.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $BlockedUsers = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-BlockedSenderAddress'

        if ($BlockedUsers) {
            $GraphRequest = foreach ($User in $BlockedUsers) {
                # Parse the reason to make it more readable
                $ReasonParts = $User.Reason -split ';'
                $LimitType = ($ReasonParts | Where-Object { $_ -like 'ExceedingLimitType=*' }) -replace 'ExceedingLimitType=', ''
                $InternalCount = ($ReasonParts | Where-Object { $_ -like 'InternalRecipientCountToday=*' }) -replace 'InternalRecipientCountToday=', ''
                $ExternalCount = ($ReasonParts | Where-Object { $_ -like 'ExternalRecipientCountToday=*' }) -replace 'ExternalRecipientCountToday=', ''

                [PSCustomObject]@{
                    SenderAddress   = $User.SenderAddress
                    Reason          = $User.Reason
                    BlockType       = if ($LimitType) { "$LimitType recipient limit exceeded" } else { 'Email sending limit exceeded' }
                    CreatedDatetime = $User.CreatedDatetime
                    ChangedDatetime = $User.ChangedDatetime
                    TemporaryBlock  = $User.TemporaryBlock
                    InternalCount   = $InternalCount
                    ExternalCount   = $ExternalCount
                }
            }
        } else {
            $GraphRequest = @()
        }

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
