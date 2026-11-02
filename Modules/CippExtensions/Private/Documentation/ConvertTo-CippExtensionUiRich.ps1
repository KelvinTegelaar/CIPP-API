function ConvertTo-CippExtensionUiRich {
    <#
        .SYNOPSIS
        Encodes text, then turns **bold** markers into <strong>.
    #>
    param([AllowNull()][string]$Text)
    (ConvertTo-CippExtensionUiText $Text) -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'
}
