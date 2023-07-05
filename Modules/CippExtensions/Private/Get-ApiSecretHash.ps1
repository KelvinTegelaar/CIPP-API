function Get-ApiSecretHash {
    Param($Secret)
    $StringBuilder = New-Object System.Text.StringBuilder
    [System.Security.Cryptography.HashAlgorithm]::Create('SHA256').ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Secret)) | ForEach-Object {
        [Void]$StringBuilder.Append($_.ToString('x2'))
    }
    $StringBuilder.ToString()
}
