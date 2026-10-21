function ConvertTo-HuduUiRich {
    <#
        .SYNOPSIS
        Encodes text, then turns **bold** markers into <strong>.
    #>
    param([AllowNull()][string]$Text)
    (ConvertTo-HuduUiText $Text) -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'
}
