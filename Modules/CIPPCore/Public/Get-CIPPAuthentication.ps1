
function Get-CIPPAuthentication {
    [CmdletBinding()]
    param (
        $APIName = 'Get Keyvault Authentication'
    )
    $Variables = @('ApplicationID', 'ApplicationSecret', 'TenantID', 'RefreshToken')

    try {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
            $Table = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-AzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            if (!$Secret) {
                throw 'Development variables not set'
            }
            foreach ($Var in $Variables) {
                if ($Secret.$Var) {
                    Set-Item -Path ENV:$Var -Value $Secret.$Var -Force -ErrorAction Stop
                }
            }
        } else {
            Connect-AzAccount -Identity
            $SubscriptionId = $ENV:WEBSITE_OWNER_NAME -split '\+' | Select-Object -First 1
            $null = Set-AzContext -SubscriptionId $SubscriptionId
            $keyvaultname = ($ENV:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            $Variables | ForEach-Object {
                Set-Item -Path ENV:$_ -Value (Get-AzKeyVaultSecret -VaultName $keyvaultname -Name $_ -AsPlainText -ErrorAction Stop) -Force
            }
        }
        $ENV:SetFromProfile = $true
        Write-LogMessage -message 'Reloaded authentication data from KeyVault' -Sev 'debug' -API 'CIPP Authentication'

        return $true
    } catch {
        Write-LogMessage -message 'Could not retrieve keys from Keyvault' -Sev 'CRITICAL' -API 'CIPP Authentication' -LogData (Get-CippException -Exception $_)
        return $false
    }
}
