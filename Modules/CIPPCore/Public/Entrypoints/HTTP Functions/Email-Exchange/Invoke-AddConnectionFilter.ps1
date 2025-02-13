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
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $RequestParams = $Request.Body.PowerShellCommand |
    ConvertFrom-Json |
    Select-Object -Property *, @{Name='identity'; Expression={$_.name}} -ExcludeProperty GUID, comments, name

    $Tenants = ($Request.body.selectedTenants).value
    $Result = foreach ($Tenantfilter in $tenants) {
        try {
            $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Set-HostedConnectionFilterPolicy' -cmdParams $RequestParams
            "Successfully created Connectionfilter for $tenantfilter."
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $tenantfilter -message "Updated Connection filter rule for $($tenantfilter)" -sev Info
        } catch {
            "Could not create create Connection Filter rule for $($tenantfilter): $($_.Exception.message)"
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $tenantfilter -message "Could not create create connection filter rule for $($tenantfilter): $($_.Exception.message)" -sev Error
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
