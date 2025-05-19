
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
                    Set-Item -Path env:$Var -Value $Secret.$Var -Force -ErrorAction Stop
                }
            }
            Write-Host "Got secrets from dev storage. ApplicationID: $env:ApplicationID"
            #Get list of tenants that have 'directTenant' set to true
            $tenants = Get-Tenants | Where-Object -Property delegatedPrivilegeStatus -EQ 'directTenant'
            if ($tenants) {
                Write-Host "Found $($tenants.Count) tenants with directTenant set to true"
                $tenants | ForEach-Object {
                    $name = $_.customerId -replace '-', '_'
                    if ($secret.$name) {
                        $name = $_.customerId
                        Set-Item -Path env:$name -Value $secret.$name -Force
                    }
                }
            }
        } else {
            Write-Information 'Connecting to Azure'
            Connect-AzAccount -Identity
            $SubscriptionId = $env:WEBSITE_OWNER_NAME -split '\+' | Select-Object -First 1
            try {
                $Context = Get-AzContext
                if ($Context.Subscription) {
                    #Write-Information "Current context: $($Context | ConvertTo-Json)"
                    if ($Context.Subscription.Id -ne $SubscriptionId) {
                        Write-Information "Setting context to subscription $SubscriptionId"
                        $null = Set-AzContext -SubscriptionId $SubscriptionId
                    }
                }
            } catch {
                Write-Information "ERROR: Could not set context to subscription $SubscriptionId."
            }

            $keyvaultname = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
            #Get list of tenants that have 'directTenant' set to true
            $tenants = Get-Tenants | Where-Object -Property delegatedPrivilegeStatus -EQ 'directTenant'
            if ($tenants) {
                $tenants | ForEach-Object {
                    $name = $_.tenantId -replace '-', '_'
                    $secret = Get-AzKeyVaultSecret -VaultName $keyvaultname -Name $name -AsPlainText -ErrorAction Stop
                    if ($secret) {
                        #set the name back to the original tenantId
                        $name = $_.customerId
                        Set-Item -Path env:$name -Value $secret -Force
                    }
                }
            }
            $Variables | ForEach-Object {
                Set-Item -Path env:$_ -Value (Get-AzKeyVaultSecret -VaultName $keyvaultname -Name $_ -AsPlainText -ErrorAction Stop) -Force
            }
        }
        $env:SetFromProfile = $true
        Write-LogMessage -message 'Reloaded authentication data from KeyVault' -Sev 'debug' -API 'CIPP Authentication'

        return $true
    } catch {
        Write-LogMessage -message 'Could not retrieve keys from Keyvault' -Sev 'CRITICAL' -API 'CIPP Authentication' -LogData (Get-CippException -Exception $_)
        return $false
    }
}
