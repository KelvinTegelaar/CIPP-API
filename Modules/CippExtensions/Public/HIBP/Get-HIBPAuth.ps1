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
            $null = Connect-AzAccount -Identity
            $SubscriptionId = $env:WEBSITE_OWNER_NAME -split '\+' | Select-Object -First 1
            $null = Set-AzContext -SubscriptionId $SubscriptionId

            $VaultName = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            try {
                $Secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'HIBP' -AsPlainText -ErrorAction Stop
            } catch {
                $Secret = $null
            }

            if ([string]::IsNullOrEmpty($Secret) -and $env:CIPP_HOSTED -eq 'true') {
                $VaultName = 'hibp-kv'
                if ($SubscriptionId -ne $env:CIPP_HOSTED_KV_SUB -and $env:CIPP_HOSTED_KV_SUB -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
                    $null = Set-AzContext -SubscriptionId $env:CIPP_HOSTED_KV_SUB
                }
                $Secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'HIBP' -AsPlainText
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
