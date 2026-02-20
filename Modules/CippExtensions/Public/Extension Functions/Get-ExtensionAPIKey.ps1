function Get-ExtensionAPIKey {
    <#
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Extension,
        [switch]$Force
    )

    $Var = "Ext_$Extension"
    $APIKey = Get-Item -Path "env:$Var" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value
    if ($APIKey -and -not $Force) {
        Write-Information "Using cached API Key for $Extension"
    } else {
        Write-Information "Retrieving API Key for $Extension"
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $APIKey = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq '$Extension' and RowKey eq '$Extension'").APIKey
        } else {
            $keyvaultname = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            $APIKey = (Get-CippKeyVaultSecret -VaultName $keyvaultname -Name $Extension -AsPlainText)
        }
        Set-Item -Path "env:$Var" -Value $APIKey -Force -ErrorAction SilentlyContinue
    }
    return $APIKey
}
