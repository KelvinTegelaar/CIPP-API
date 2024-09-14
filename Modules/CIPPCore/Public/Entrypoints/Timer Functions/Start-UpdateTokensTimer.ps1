function Start-UpdateTokensTimer {
    <#
    .SYNOPSIS
    Start the Update Tokens Timer
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    if ($PSCmdlet.ShouldProcess('Start-UpdateTokensTimer', 'Starting Update Tokens Timer')) {

        # Get the current universal time in the default string format.
        $currentUTCtime = (Get-Date).ToUniversalTime()

        $Refreshtoken = (Get-GraphToken -ReturnRefresh $true).Refresh_token

        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
            $Table = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            if ($Secret) {
                $Secret.RefreshToken = $Refreshtoken
                Add-AzDataTableEntity @Table -Entity $Secret -Force
            } else {
                Write-LogMessage -message 'Could not update refresh token. Will try again in 7 days.' -sev 'CRITICAL'
            }
        } else {
            if ($env:MSI_SECRET) {
                Disable-AzContextAutosave -Scope Process | Out-Null
                $AzSession = Connect-AzAccount -Identity
            }
            $KV = $ENV:WEBSITE_DEPLOYMENT_ID
            if ($Refreshtoken) {
                Set-AzKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $Refreshtoken -AsPlainText -Force)
            } else {
                Write-LogMessage -message 'Could not update refresh token. Will try again in 7 days.' -sev 'CRITICAL'
            }
        }

        # Write an information log with the current time.
        Write-Information "PowerShell timer trigger function ran! TIME: $currentUTCtime"
    }
}
