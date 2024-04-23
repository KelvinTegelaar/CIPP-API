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
        # Generate a complex password with a maximum of 100 tries
        $maxTries = 100
        $tryCount = 0

        do {
            $Password = -join ('abcdefghkmnrstuvwxyzABCDEFGHKLMNPRSTUVWXYZ23456789$%&*#'.ToCharArray() | Get-Random -Count $count)

            $containsUppercase = $Password -cmatch '[A-Z]'
            $containsLowercase = $Password -cmatch '[a-z]'
            $containsDigit = $Password -cmatch '\d'
            $containsSpecialChar = $Password -cmatch "[$%&*#]"

            $isComplex = $containsUppercase -and $containsLowercase -and $containsDigit -and $containsSpecialChar

            $tryCount++
        } while (!$isComplex -and ($tryCount -lt $maxTries))

        $Password
    }
}
