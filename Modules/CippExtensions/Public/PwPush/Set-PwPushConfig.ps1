function Set-PwPushConfig {
    <#
    .SYNOPSIS
    Sets PwPush configuration

    .DESCRIPTION
    Sets PwPush configuration from CIPP Extension config

    .PARAMETER Configuration
    Configuration object
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $Configuration
    )
    $InitParams = @{}
    if ($Configuration.BaseUrl) {
        $InitParams.BaseUrl = $Configuration.BaseUrl
    }
    if (![string]::IsNullOrEmpty($Configuration.EmailAddress)) {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $ApiKey = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'PWPush' and RowKey eq 'PWPush'").APIKey
        } else {
            $null = Connect-AzAccount -Identity
            $ApiKey = Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name 'PWPush' -AsPlainText
        }
        if (![string]::IsNullOrEmpty($ApiKey)) {
            $InitParams.APIKey = $ApiKey
            $InitParams.EmailAddress = $Configuration.EmailAddress
        }
    }
    if ($PSCmdlet.ShouldProcess('Initialize-PassPushPosh')) {
        Initialize-PassPushPosh @InitParams
    }
}
