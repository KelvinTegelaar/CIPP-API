function Get-HIBPAuth {
    $Var = 'Ext_HIBP'
    $APIKey = Get-Item -Path "env:$Var" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value
    if ($APIKey) {
        Write-Information 'Using cached API Key for HIBP'
        $Secret = $APIKey
    } else {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'HIBP' and RowKey eq 'HIBP'").APIKey
        } else {
            $VaultName = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            try {
                $Secret = Get-CippKeyVaultSecret -VaultName $VaultName -Name 'HIBP' -AsPlainText -ErrorAction Stop
            } catch {
                $Secret = $null
            }

            if ([string]::IsNullOrEmpty($Secret) -and $env:CIPP_HOSTED -eq 'true') {
                $VaultName = 'hibp-kv'
                $Secret = Get-CippKeyVaultSecret -VaultName $VaultName -Name 'HIBP' -AsPlainText
            }
        }
        Set-Item -Path "env:$Var" -Value $APIKey -Force -ErrorAction SilentlyContinue
    }

    return @{
        'User-Agent'   = "CIPP-$($env:TenantID)"
        'Accept'       = 'application/json'
        'api-version'  = '3'
        'hibp-api-key' = $Secret
    }
}
