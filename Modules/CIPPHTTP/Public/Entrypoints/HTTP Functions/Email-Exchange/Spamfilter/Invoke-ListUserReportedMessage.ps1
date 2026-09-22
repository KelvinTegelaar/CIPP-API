function Invoke-ListUserReportedMessage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    .DESCRIPTION
        Retrieves the raw EML content of a user reported message by its Internet Message ID. Tries the quarantine store first (Export-QuarantineMessage), then falls back to reading the message from the recipient's or reporter's mailbox via Graph.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $InternetMessageId = $Request.Query.InternetMessageId
    $Mailboxes = @($Request.Query.RecipientEmail, $Request.Query.ReporterEmail) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    try {
        if ([string]::IsNullOrWhiteSpace($InternetMessageId)) { throw 'This submission has no Internet Message ID, so the message content cannot be retrieved.' }

        $EmlBase64 = $null
        $Source = $null
        $Errors = [System.Collections.Generic.List[string]]::new()

        # A reported message that was (or later got) quarantined can always be exported from quarantine
        try {
            $Quarantined = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantineMessage' -cmdParams @{ MessageId = $InternetMessageId } | Select-Object -First 1
            if ($Quarantined.Identity) {
                $Export = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Export-QuarantineMessage' -cmdParams @{ Identity = $Quarantined.Identity }
                if (-not [string]::IsNullOrEmpty($Export.Eml)) {
                    $EmlBase64 = $Export.Eml
                    $Source = 'Quarantine'
                }
            }
        } catch {
            $Errors.Add("Quarantine lookup: $(Get-NormalizedError -Message $_.Exception.Message)")
        }

        # Otherwise the copy in the mailbox (Deleted Items included) is the only source left
        if (-not $EmlBase64) {
            $SafeMessageId = ConvertTo-CIPPODataFilterValue -Value $InternetMessageId -Type String
            $Filter = [System.Uri]::EscapeDataString("internetMessageId eq '$SafeMessageId'")
            foreach ($Mailbox in $Mailboxes) {
                try {
                    $SafeMailbox = [System.Uri]::EscapeDataString($Mailbox)
                    $Message = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$SafeMailbox/messages?`$filter=$Filter&`$select=id&`$top=5" -tenantid $TenantFilter | Select-Object -First 1
                    if ($Message.id) {
                        $Mime = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$SafeMailbox/messages/$($Message.id)/`$value" -tenantid $TenantFilter -ReturnRawResponse
                        if ($Mime.StatusCode -eq 200 -and -not [string]::IsNullOrEmpty($Mime.Content)) {
                            $EmlBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$Mime.Content))
                            $Source = 'Mailbox'
                            break
                        }
                    }
                } catch {
                    $Errors.Add("Mailbox $($Mailbox): $(Get-NormalizedError -Message $_.Exception.Message)")
                }
            }
        }

        if (-not $EmlBase64) {
            $Detail = if ($Errors.Count -gt 0) { " ($($Errors -join ' | '))" } else { '' }
            throw "The reported message could not be retrieved: it is not in quarantine and could not be read from the mailbox. Mailbox retrieval requires the Mail.Read Graph permission on the CIPP-SAM application.$Detail"
        }

        $EmlContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($EmlBase64))
        $Header = ($EmlContent -split "\r?\n\r?\n", 2)[0]
        $Body = @{
            'InternetMessageId' = $InternetMessageId
            'Message'           = $EmlContent
            'EmlBase64'         = $EmlBase64
            'Header'            = $Header
            'Source'            = $Source
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Body = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
