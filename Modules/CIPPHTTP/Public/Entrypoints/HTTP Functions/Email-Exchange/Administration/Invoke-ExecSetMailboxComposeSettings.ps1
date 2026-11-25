function Invoke-ExecSetMailboxComposeSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    .DESCRIPTION
        Sets the Outlook on the web compose settings of one mailbox: undo send delay, always show From and Bcc, forgotten attachment reminder, default reply action, message format, read receipt handling, link previews and default font. Settings left out are not changed.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Mailbox UPN or address.
    $UserID = $Request.Body.ID
    if (-not $UserID) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ID is required' } })
    }

    $Params = @{ Identity = $UserID }
    $Invalid = [System.Collections.Generic.List[string]]::new()

    # Undo send delay in seconds, 0 to 10. 0 turns undo send off.
    $UndoInterval = "$($Request.Body.MailSendUndoInterval)"
    if ($UndoInterval -ne '') {
        $Seconds = 0
        if ([int]::TryParse($UndoInterval, [ref]$Seconds) -and $Seconds -ge 0 -and $Seconds -le 10) {
            $Params.MailSendUndoInterval = $Seconds
        } else {
            $Invalid.Add('MailSendUndoInterval must be a whole number from 0 to 10')
        }
    }

    # true or false for each; leave a setting out to keep its current value.
    $OnOff = [ordered]@{
        AlwaysShowFrom               = $Request.Body.AlwaysShowFrom
        AlwaysShowBcc                = $Request.Body.AlwaysShowBcc
        CheckForForgottenAttachments = $Request.Body.CheckForForgottenAttachments
        IsReplyAllTheDefaultResponse = $Request.Body.IsReplyAllTheDefaultResponse
        LinkPreviewEnabled           = $Request.Body.LinkPreviewEnabled
    }
    foreach ($Setting in $OnOff.GetEnumerator()) {
        $Value = "$($Setting.Value)"
        if ($Value -eq '') { continue }
        if ($Value -in @('true', 'false')) { $Params[$Setting.Key] = $Value -eq 'true' } else { $Invalid.Add("$($Setting.Key) must be true or false") }
    }

    # Default compose font name, for example Aptos.
    $FontName = "$($Request.Body.DefaultFontName)".Trim()
    if ($FontName -ne '') { $Params.DefaultFontName = $FontName }
    # Default font size: 1-7 is the legacy scale (3 is 12pt), 8-72 is a point size.
    $FontSize = "$($Request.Body.DefaultFontSize)"
    if ($FontSize -ne '') {
        $Size = 0
        if ([int]::TryParse($FontSize, [ref]$Size) -and $Size -ge 1 -and $Size -le 72) { $Params.DefaultFontSize = $Size } else { $Invalid.Add('DefaultFontSize must be a whole number from 1 to 72') }
    }
    # Default font colour as #xxxxxx.
    $FontColor = "$($Request.Body.DefaultFontColor)"
    if ($FontColor -ne '') {
        if ($FontColor -match '^#[0-9A-Fa-f]{6}$') { $Params.DefaultFontColor = $FontColor } else { $Invalid.Add('DefaultFontColor must be a six-digit hex colour such as #000000') }
    }

    switch ("$($Request.Body.DefaultFormat)") {
        '' {}
        'Html' { $Params.DefaultFormat = 'Html' }
        'PlainText' { $Params.DefaultFormat = 'PlainText' }
        default { $Invalid.Add('DefaultFormat must be Html or PlainText') }
    }
    switch ("$($Request.Body.ReadReceiptResponse)") {
        '' {}
        'DoNotAutomaticallySend' { $Params.ReadReceiptResponse = 'DoNotAutomaticallySend' }
        'AlwaysSend' { $Params.ReadReceiptResponse = 'AlwaysSend' }
        'NeverSend' { $Params.ReadReceiptResponse = 'NeverSend' }
        default { $Invalid.Add('ReadReceiptResponse must be DoNotAutomaticallySend, AlwaysSend or NeverSend') }
    }

    if ($Invalid.Count -gt 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = $Invalid -join '. ' } })
    }
    if ($Params.Count -eq 1) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Choose at least one setting to change' } })
    }

    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxMessageConfiguration' -cmdParams $Params -Anchor $UserID
        $Result = "Updated Outlook compose settings for $UserID"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update Outlook compose settings for $UserID. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
