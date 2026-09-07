function Get-CIPPSharePointCopyJobQueueLogs {
    <#
    .SYNOPSIS
        Peeks encrypted SharePoint copy job log messages from the job Azure Storage queue.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobQueueUri,

        [Parameter(Mandatory = $true)]
        $EncryptionKey,

        [int]$MaxMessages = 100
    )

    if ([string]::IsNullOrWhiteSpace($JobQueueUri)) {
        return @()
    }

    $KeyBytes = if ($EncryptionKey -is [byte[]]) {
        $EncryptionKey
    } else {
        $KeyText = [string]$EncryptionKey
        if ([string]::IsNullOrWhiteSpace($KeyText)) { throw 'EncryptionKey is empty.' }
        try {
            [Convert]::FromBase64String($KeyText)
        } catch {
            [System.Text.Encoding]::UTF8.GetBytes($KeyText)
        }
    }

    $Logs = [System.Collections.Generic.List[object]]::new()
    $Separator = if ($JobQueueUri -match '\?') { '&' } else { '?' }
    $Remaining = $MaxMessages
    $Page = 0

    while ($Remaining -gt 0 -and $Page -lt 8) {
        $BatchSize = [Math]::Min(32, $Remaining)
        $Uri = "$JobQueueUri${Separator}peekonly=true&numofmessages=$BatchSize&format=json"
        $Response = Invoke-RestMethod -Uri $Uri -Method Get -ErrorAction Stop

        $Messages = @()
        if ($null -ne $Response.QueueMessages) {
            $Messages = @($Response.QueueMessages)
        } elseif ($null -ne $Response.QueueMessage) {
            $Messages = @($Response.QueueMessage)
        }

        if ($Messages.Count -eq 0) { break }

        foreach ($Message in $Messages) {
            $BodyText = [string]($Message.MessageText ?? $Message.messageText ?? '')
            if ([string]::IsNullOrWhiteSpace($BodyText)) { continue }

            try {
                $EnvelopeJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($BodyText))
                $Envelope = $EnvelopeJson | ConvertFrom-Json
                if (-not $Envelope.IV -or -not $Envelope.Content) { continue }

                $Aes = [System.Security.Cryptography.Aes]::Create()
                try {
                    $Aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
                    $Aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
                    $Aes.Key = $KeyBytes
                    $Aes.IV = [Convert]::FromBase64String([string]$Envelope.IV)
                    $Decryptor = $Aes.CreateDecryptor()
                    $Cipher = [Convert]::FromBase64String([string]$Envelope.Content)
                    $PlainBytes = $Decryptor.TransformFinalBlock($Cipher, 0, $Cipher.Length)
                    $PlainJson = [System.Text.Encoding]::UTF8.GetString($PlainBytes)
                } finally {
                    $Aes.Dispose()
                }

                if ([string]::IsNullOrWhiteSpace($PlainJson)) { continue }
                [void]$Logs.Add(($PlainJson | ConvertFrom-Json))
            } catch {
                continue
            }
        }

        $Remaining -= $Messages.Count
        $Page++
        if ($Messages.Count -lt $BatchSize) { break }
    }

    return @($Logs)
}
