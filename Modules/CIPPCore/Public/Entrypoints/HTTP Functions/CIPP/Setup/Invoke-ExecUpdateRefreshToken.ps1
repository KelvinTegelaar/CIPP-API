using namespace System.Net

Function Invoke-ExecUpdateRefreshToken {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $KV = $env:WEBSITE_DEPLOYMENT_ID

    try {
        # Handle refresh token update
        #make sure we get the latest authentication:
        $auth = Get-CIPPAuthentication
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            if ($env:ApplicationId -eq $Request.body.tenantId) {
                $Secret.RefreshToken = $Request.body.RefreshToken
            } else {
                Write-Host "$($env:Applicationid) does not match $($Request.body.tenantId)"
                $name = $Request.body.tenantId -replace '-', '_'
                $secret | Add-Member -MemberType NoteProperty -Name $name -Value $Request.body.refreshtoken -Force
            }
            Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
        } else {
            if ($env:ApplicationId -eq $Request.body.tenantId) {
                Set-AzKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $Request.body.refreshtoken -AsPlainText -Force)
            } else {
                $name = $Request.body.tenantId -replace '-', '_'
                Set-AzKeyVaultSecret -VaultName $kv -Name $name -SecretValue (ConvertTo-SecureString -String $Request.body.refreshtoken -AsPlainText -Force)
            }
        }
        $InstanceId = Start-UpdatePermissionsOrchestrator #start the CPV refresh immediately while wizard still runs.


        $Results = @{
            'message'  = "Successfully updated your stored authentication for $($request.body.tenantId)."
            'tenantId' = $Request.body.tenantId
        }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.InvocationInfo.ScriptLineNumber):  $($_.Exception.message)"; severity = 'failed' }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
