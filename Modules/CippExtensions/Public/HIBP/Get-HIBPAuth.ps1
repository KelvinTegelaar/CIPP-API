function Get-HIBPAuth {
    $Var = 'Ext_HIBP'
    $APIKey = Get-Item -Path "ENV:$Var" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value
    if ($APIKey) {
        Write-Information 'Using cached API Key for HIBP'
    } else {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = (Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'HIBP' and RowKey eq 'HIBP'").APIKey
        } else {
            $null = Connect-AzAccount -Identity
            $VaultName = ($ENV:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            try {
                $Secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'HIBP' -AsPlainText -ErrorAction Stop
            } catch {
                $Secret = $null
            }

            if ([string]::IsNullOrEmpty($Secret) -and $ENV:WEBSITE_OWNER_NAME -like '3e625d35-bf18-4e55*' -or $ENV:WEBSITE_OWNER_NAME -like '61e84181-ff2a-4ba3*') {
                $VaultName = 'hibp-kv'
                $Secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'HIBP' -AsPlainText
            }
        }
        Set-Item -Path "ENV:$Var" -Value $APIKey -Force -ErrorAction SilentlyContinue
    }

    return @{
        'User-Agent'   = "CIPP-$($ENV:TenantID)"
        'Accept'       = 'application/json'
        'api-version'  = '3'
        'hibp-api-key' = $Secret
    }
}
