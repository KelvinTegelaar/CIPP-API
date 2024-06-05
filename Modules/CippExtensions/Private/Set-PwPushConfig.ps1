function Set-PwPushConfig {
    param(
        $Configuration
    )
    $InitParams = @{}
    if ($Configuration.BaseUrl) {
        $InitParams.BaseUrl = $Configuration.BaseUrl
    }
    if ($Configuration.EmailAddress) {
        $null = Connect-AzAccount -Identity
        $ApiKey = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name 'PWPush' -AsPlainText)
        if ($ApiKey) {
            $InitParams.ApiKey = $ApiKey
            $InitParams.EmailAddress = $Configuration.EmailAddress
        }
    }
    Initialize-PassPushPosh @InitParams
}