function Get-PwPushAccount {
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).PWPush
    if ($Configuration.Enabled -eq $true -and $Configuration.UseBearerAuth -eq $true) {
        Set-PwPushConfig -Configuration $Configuration
        Get-PushAccount
    } else {
        return @(@{
                name = 'PWPush Pro is not enabled or configured. Make sure to save the configuration first.';
                id   = ''
            })
    }
}
