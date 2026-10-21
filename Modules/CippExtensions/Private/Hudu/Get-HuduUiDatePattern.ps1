function Get-HuduUiDatePattern {
    <#
        .SYNOPSIS
        A short month-name date pattern in the culture's own day and month order, for example d MMM yyyy.
    #>
    param([cultureinfo]$Culture = [cultureinfo]::GetCultureInfo('en-GB'))
    "$($Culture.DateTimeFormat.MonthDayPattern -creplace 'MMMM', 'MMM') yyyy"
}
