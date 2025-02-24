using namespace System.Net

Function Invoke-RemoveSpamfilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Spamfilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Query.tenantFilter
    $Name = $Request.Query.name ?? $Request.Body.name


    try {
        $Params = @{
            Identity = $Name
        }
        $Cmdlet = 'Remove-HostedContentFilterRule'
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $Cmdlet -cmdParams $Params -useSystemMailbox $true
        $Cmdlet = 'Remove-HostedContentFilterPolicy'
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $Cmdlet -cmdParams $Params -useSystemMailbox $true
        $Result = "Deleted Spam filter rule $($Name)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete Spam filter rule $($Name) - $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
