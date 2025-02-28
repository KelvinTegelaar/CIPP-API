using namespace System.Net

Function Invoke-AddSpamFilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $RequestParams = $Request.Body.PowerShellCommand | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty GUID, comments
    $RequestPriority = $Request.Body.Priority

    $Tenants = ($Request.body.selectedTenants).value
    $Result = foreach ($TenantFilter in $tenants) {
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-HostedContentFilterPolicy' -cmdParams $RequestParams
            $Domains = (New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AcceptedDomain').name
            $ruleparams = @{
                'name'                      = "$($RequestParams.name)"
                'hostedcontentfilterpolicy' = "$($RequestParams.name)"
                'recipientdomainis'         = @($domains)
                'Enabled'                   = $true
                'Priority'                  = $RequestPriority
            }
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-HostedContentFilterRule' -cmdParams $ruleparams
            "Successfully created spamfilter for $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created spamfilter for $TenantFilter." -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not create spamfilter rule for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not create spamfilter rule for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
