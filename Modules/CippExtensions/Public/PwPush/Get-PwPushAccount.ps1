function Get-PwPushAccount {
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $ParsedConfig = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ErrorAction SilentlyContinue
    $Configuration = $ParsedConfig.PWPush
    if ($Configuration.Enabled -eq $true -and $Configuration.UseBearerAuth -eq $true) {
        Set-PwPushConfig -Configuration $Configuration -FullConfiguration $ParsedConfig
        Get-PushAccount
    } else {
        return @(@{
                name = 'PWPush Pro is not enabled or configured. Make sure to save the configuration first.';
                id   = ''
            })
    }
}
