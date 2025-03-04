using namespace System.Net

Function Invoke-AddConnectionFilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.ConnectionFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $RequestParams = $Request.Body.PowerShellCommand |
        ConvertFrom-Json |
        Select-Object -Property *, @{Name = 'identity'; Expression = { $_.name } } -ExcludeProperty GUID, comments, name

    $Tenants = ($Request.Body.selectedTenants).value
    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-HostedConnectionFilterPolicy' -cmdParams $RequestParams
            "Successfully created Connection filter for $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created Connection filter for $TenantFilter." -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Failed to create Connection Filter rule for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to create connection filter rule for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
