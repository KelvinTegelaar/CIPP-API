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

    $KV = $env:WEBSITE_DEPLOYMENT_ID

    try {
        # Handle refresh token update
        #make sure we get the latest authentication:
        $auth = Get-CIPPAuthentication
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"

            if ($env:TenantID -eq $Request.body.tenantId) {
                $Secret | Add-Member -MemberType NoteProperty -Name 'RefreshToken' -Value $Request.body.refreshtoken -Force
            } else {
                Write-Host "$($env:TenantID) does not match $($Request.body.tenantId)"
                $name = $Request.body.tenantId -replace '-', '_'
                $secret | Add-Member -MemberType NoteProperty -Name $name -Value $Request.body.refreshtoken -Force
            }
            Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
        } else {
            if ($env:TenantID -eq $Request.body.tenantId) {
                Set-AzKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $Request.body.refreshtoken -AsPlainText -Force)
            } else {
                Write-Host "$($env:TenantID) does not match $($Request.body.tenantId) - we're adding a new secret for the tenant."
                $name = $Request.body.tenantId
                try {
                    Set-AzKeyVaultSecret -VaultName $kv -Name $name -SecretValue (ConvertTo-SecureString -String $Request.body.refreshtoken -AsPlainText -Force)
                } catch {
                    Write-Host "Failed to set secret $name in KeyVault. $($_.Exception.Message)"
                    throw $_
                }
            }
        }
        $InstanceId = Start-UpdatePermissionsOrchestrator #start the CPV refresh immediately while wizard still runs.

        if ($request.body.tenantId -eq $env:TenantID) {
            $TenantName = 'your partner tenant'
        } else {
            $TenantName = $request.body.tenantId
        }
        $Results = @{
            'resultText' = "Successfully updated the credentials for $($TenantName). You may continue to the next step, or add additional tenants if required."
            'state'      = 'success'
        }
    } catch {
        $Results = [pscustomobject]@{
            'Results' = @{
                resultText = "Failed. $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.message)"
                state      = 'failed'
            }
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Results
            })

    }
}
