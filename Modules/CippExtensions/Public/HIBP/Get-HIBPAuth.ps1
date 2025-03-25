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
            $SubscriptionId = $ENV:WEBSITE_OWNER_NAME -split '\+' | Select-Object -First 1
            $null = Set-AzContext -SubscriptionId $SubscriptionId

            $VaultName = ($ENV:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            try {
                $Secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'HIBP' -AsPlainText -ErrorAction Stop
            } catch {
                $Secret = $null
            }

            if ([string]::IsNullOrEmpty($Secret) -and $ENV:CIPP_HOSTED -eq 'true') {
                $VaultName = 'hibp-kv'
                if ($SubscriptionId -ne $ENV:CIPP_HOSTED_KV_SUB -and $ENV:CIPP_HOSTED_KV_SUB -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
                    $null = Set-AzContext -SubscriptionId $ENV:CIPP_HOSTED_KV_SUB
                }
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
