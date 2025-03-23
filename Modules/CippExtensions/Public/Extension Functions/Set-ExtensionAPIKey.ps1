function Set-ExtensionAPIKey {
    <#
    .FUNCTIONALITY
        Internal
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Scope = 'Function')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Extension,
        [Parameter(Mandatory = $true)]
        [string]$APIKey
    )

    if ($PSCmdlet.ShouldProcess('API Key', "Set API Key for $Extension")) {
        $Var = "Ext_$Extension"
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = [PSCustomObject]@{
                'PartitionKey' = $Extension
                'RowKey'       = $Extension
                'APIKey'       = $APIKey
            }
            Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
        } else {
            $keyvaultname = ($ENV:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            $null = Connect-AzAccount -Identity
            $null = Set-AzKeyVaultSecret -VaultName $keyvaultname -Name $Extension -SecretValue (ConvertTo-SecureString -AsPlainText -Force -String $APIKey)
        }
        Set-Item -Path "ENV:$Var" -Value $APIKey -Force -ErrorAction SilentlyContinue
    }
    return $true
}
