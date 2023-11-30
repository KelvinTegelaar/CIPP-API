
function Get-CIPPAuthentication {
    [CmdletBinding()]
    param (
        $APIName = "Get Keyvault Authentication"
    )

    try {
        Connect-AzAccount -Identity
        
        @('ApplicationId','ApplicationSecret','TenantId','RefreshToken') | Foreach-Object {
            Set-Item -path ENV:$_ -value (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name $_ -AsPlainText -ErrorAction Stop) -Force
        }
        
        $ENV:SetFromProfile = $true
        Write-LogMessage -message "Reloaded authentication data from KeyVault" -Sev 'debug' -API "CIPP Authentication"

        return $true 
    }
    catch {
        Write-LogMessage -message "Could not retrieve keys from Keyvault: $($_.Exception.Message)" -Sev 'CRITICAL' -API "CIPP Authentication"
        return $false
    }
}


