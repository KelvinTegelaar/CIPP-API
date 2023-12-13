function New-passwordString {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param (
        [int]$count = 12
    )
    $SettingsTable = Get-CippTable -tablename 'Settings'
    $PasswordType = (Get-CIPPAzDataTableEntity @SettingsTable).passwordType
    if ($PasswordType -eq 'Correct-Battery-Horse') {
        $Words = Get-Content .\words.txt
        (Get-Random -InputObject $words -Count 4) -join '-'
    } else {
        -join ('abcdefghkmnrstuvwxyzABCDEFGHKLMNPRSTUVWXYZ23456789$%&*#'.ToCharArray() | Get-Random -Count $count)
    }
}
