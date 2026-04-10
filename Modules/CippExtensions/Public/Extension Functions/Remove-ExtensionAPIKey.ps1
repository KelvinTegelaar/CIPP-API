function Remove-ExtensionAPIKey {
    <#
    .FUNCTIONALITY
        Internal
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Extension
    )

    $Var = "Ext_$Extension"
    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
        $DevSecretRows = Get-AzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq '$Extension'"
        if ($DevSecretRows) {
            Remove-AzDataTableEntity @DevSecretsTable -Entity @($DevSecretRows) -Force -ErrorAction Stop
            Write-Information "Deleted $(@($DevSecretRows).Count) DevSecrets row(s) for '$Extension'."
        } else {
            Write-Information "No existing DevSecrets row found for '$Extension' to delete."
        }
    } else {
        $keyvaultname = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
        try {
            $null = Remove-CippKeyVaultSecret -VaultName $keyvaultname -Name $Extension
        } catch {
            Write-Warning "Unable to delete secret '$Extension' from '$keyvaultname'"
        }
    }

    Remove-Item -Path "env:$Var" -Force -ErrorAction SilentlyContinue

    return $true
}
