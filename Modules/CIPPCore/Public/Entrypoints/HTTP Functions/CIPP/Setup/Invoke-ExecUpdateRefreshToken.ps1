using namespace System.Net

function Invoke-ExecUpdateRefreshToken {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $KV = $env:WEBSITE_DEPLOYMENT_ID

    try {
        # Handle refresh token update
        #make sure we get the latest authentication:
        $auth = Get-CIPPAuthentication
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"

            if ($env:TenantID -eq $Request.Body.tenantId) {
                $Secret | Add-Member -MemberType NoteProperty -Name 'RefreshToken' -Value $Request.Body.refreshtoken -Force
            } else {
                Write-Host "$($env:TenantID) does not match $($Request.Body.tenantId)"
                $name = $Request.body.tenantId -replace '-', '_'
                $secret | Add-Member -MemberType NoteProperty -Name $name -Value $Request.Body.refreshtoken -Force
            }
            Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
        } else {
            if ($env:TenantID -eq $Request.Body.tenantId) {
                Set-AzKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $Request.Body.refreshtoken -AsPlainText -Force)
            } else {
                Write-Host "$($env:TenantID) does not match $($Request.Body.tenantId) - we're adding a new secret for the tenant."
                $name = $Request.Body.tenantId
                try {
                    Set-AzKeyVaultSecret -VaultName $kv -Name $name -SecretValue (ConvertTo-SecureString -String $Request.Body.refreshtoken -AsPlainText -Force)
                } catch {
                    Write-Host "Failed to set secret $name in KeyVault. $($_.Exception.Message)"
                    throw $_
                }
            }
        }
        $InstanceId = Start-UpdatePermissionsOrchestrator #start the CPV refresh immediately while wizard still runs.

        if ($Request.Body.tenantId -eq $env:TenantID) {
            $TenantName = 'your partner tenant'
        } else {
            $TenantName = $Request.Body.tenantId
        }
        $Results = @{
            'message'  = "Successfully updated the credentials for $($TenantName). You may continue to the next step, or add additional tenants if required."
            'severity' = 'success'
        }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.message)"; severity = 'failed' }
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    }
}
